const fs = require('node:fs/promises');
const path = require('node:path');
const { chromium } = require('playwright');

const repositoryRoot = __dirname;
const defaults = {
	input: path.join(repositoryRoot, 'google_fonts.json'),
	output: path.join(repositoryRoot, 'fonts'),
	timeout: 120000,
	force: false,
	headless: true,
};

function parseArguments(argumentsList) {
	const options = { ...defaults };

	for (let index = 0; index < argumentsList.length; index += 1) {
		const argument = argumentsList[index];
		if (argument === '--force') {
			options.force = true;
		} else if (argument === '--headful') {
			options.headless = false;
		} else if (argument === '--input' || argument === '--output' || argument === '--timeout') {
			const value = argumentsList[index + 1];
			if (!value) {
				throw new Error(`Missing value for ${argument}`);
			}
			options[argument.slice(2)] = argument === '--timeout' ? Number(value) : path.resolve(value);
			index += 1;
		} else if (argument === '--help' || argument === '-h') {
			console.log('Usage: node index.js [--force] [--headful] [--input path] [--output path] [--timeout milliseconds]');
			process.exit(0);
		} else {
			throw new Error(`Unknown argument: ${argument}`);
		}
	}

	if (!Number.isFinite(options.timeout) || options.timeout <= 0) {
		throw new Error('--timeout must be a positive number');
	}

	return options;
}

async function readFonts(inputPath) {
	const contents = await fs.readFile(inputPath, 'utf8');
	const fonts = JSON.parse(contents);
	if (!Array.isArray(fonts)) {
		throw new Error(`${inputPath} must contain a JSON array`);
	}
	return fonts;
}

async function saveDownload(page, url, outputPath, timeout) {
	let response;
	let navigationDownload;

	const downloadPromise = page.waitForEvent('download', { timeout: Math.min(timeout, 10000) }).catch(() => null);
	try {
		response = await page.goto(url, { waitUntil: 'domcontentloaded', timeout });
	} catch (error) {
		navigationDownload = await downloadPromise;
		if (!navigationDownload) {
			throw error;
		}
	}

	if (response) {
		const contentType = response.headers()['content-type'] || '';
		const body = await response.body();
		const isZip = body.length >= 2 && body[0] === 0x50 && body[1] === 0x4b;
		if (isZip || contentType.includes('zip') || contentType.includes('octet-stream')) {
			await fs.writeFile(outputPath, body);
			return;
		}
	}

	navigationDownload ??= await downloadPromise;
	if (navigationDownload) {
		await navigationDownload.saveAs(outputPath);
		return;
	}

	const downloadLink = page.locator('a[download], a[href*=".zip"], a[href*="download"]').first();
	if (await downloadLink.count() === 0) {
		throw new Error('The page did not expose a downloadable ZIP link');
	}

	const clickDownload = page.waitForEvent('download', { timeout });
	await downloadLink.click();
	await (await clickDownload).saveAs(outputPath);
}

async function main() {
	const options = parseArguments(process.argv.slice(2));
	const fonts = await readFonts(options.input);
	await fs.mkdir(options.output, { recursive: true });

	const browser = await chromium.launch({ headless: options.headless });
	const context = await browser.newContext({ acceptDownloads: true });
	const failures = [];

	try {
		for (const font of fonts) {
			const outputPath = path.join(options.output, `${font.id}.zip`);
			if (!options.force) {
				try {
					await fs.access(outputPath);
					console.log(`SKIP       ${font.name} -> ${outputPath}`);
					continue;
				} catch {}
			}

			const page = await context.newPage();
			try {
				await saveDownload(page, font.download_url, outputPath, options.timeout);
				console.log(`DOWNLOADED ${font.name} -> ${outputPath}`);
			} catch (error) {
				failures.push(`${font.name}: ${error.message}`);
				console.error(`FAILED     ${font.name}: ${error.message}`);
			} finally {
				await page.close();
			}
		}
	} finally {
		await context.close();
		await browser.close();
	}

	if (failures.length > 0) {
		throw new Error(`${failures.length} font download(s) failed`);
	}
}

main().catch((error) => {
	console.error(error.message);
	process.exitCode = 1;
});
