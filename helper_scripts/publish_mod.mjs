#!/usr/bin/env node
/**
 * Publish the current PlanetsLib commit to the Factorio mod portal.
 *
 * The script mirrors the packaging and upload flow used by
 * `factorio-semantic-release`:
 *
 *   1. read the mod metadata from info.json;
 *   2. package the committed tree with `git archive`;
 *   3. ask the mod portal for an upload URL;
 *   4. upload the zip and report the result.
 *
 * It publishes the version already committed in info.json. Bump the version and
 * fill in changelog.txt first, then commit and push before running this script.
 *
 * The API key is read from `.env` in the repository root. Accepted names are
 * FACTORIO_API_KEY, FACTORIO_TOKEN, and MOD_UPLOAD_API_KEY. Create a key at
 * https://factorio.com/profile with the "Upload Mods" permission (and
 * "Publish Mods" if the mod does not exist on the portal yet).
 *
 * Examples:
 *   node helper_scripts/publish_mod.mjs --dry-run
 *   node helper_scripts/publish_mod.mjs
 *   node helper_scripts/publish_mod.mjs --yes
 *   node helper_scripts/publish_mod.mjs --zip PlanetsLib_2.3.4.zip
 *
 * Requires Node.js 18 or newer (built-in fetch, FormData, and Blob).
 */

import { execFile } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { readFile, rm } from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import readline from "node:readline/promises";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(SCRIPT_DIR, "..");
const ENV_FILE = path.join(REPO_ROOT, ".env");
const INFO_FILE = path.join(REPO_ROOT, "info.json");
const CHANGELOG_FILE = path.join(REPO_ROOT, "changelog.txt");
const DEFAULT_API_BASE = "https://mods.factorio.com";
const USER_AGENT = "PlanetsLib-publish-script/1.0";
const API_KEY_VARS = ["FACTORIO_API_KEY", "FACTORIO_TOKEN", "MOD_UPLOAD_API_KEY"];
const VERSION_PATTERN = /^\d+\.\d+\.\d+$/;

const HELP = `Publish a new PlanetsLib version to the Factorio mod portal.

Usage:
  node helper_scripts/publish_mod.mjs [options]

The version is read from info.json. The script packages the current HEAD with
git archive, so commit and push the version bump and changelog first.

API key:
  Put FACTORIO_API_KEY=<key> in .env at the repository root.
  FACTORIO_TOKEN and MOD_UPLOAD_API_KEY are accepted as aliases.
  Create the key at https://factorio.com/profile with "Upload Mods" permission.

Options:
  --dry-run             Validate and package, but do not upload.
  --zip <path>          Upload an existing zip instead of building one.
  --keep-archive        Keep the generated PlanetsLib_<version>.zip.
  --yes, -y             Do not ask for confirmation.
  --allow-dirty         Allow a dirty working tree (the zip still uses HEAD).
  --allow-any-branch    Allow publishing from a branch other than main.
  --skip-version-check  Do not check whether the version is already on the portal.
  --api-base <url>      Mod portal base URL (default: ${DEFAULT_API_BASE}).
  -h, --help            Show this help.

Environment:
  FACTORIO_MOD_PORTAL_URL  Overrides the default mod portal base URL.
`;

function parseArgs(argv) {
	const options = {
		dryRun: false,
		yes: false,
		keepArchive: false,
		allowDirty: false,
		allowAnyBranch: false,
		skipVersionCheck: false,
		zip: null,
		apiBase: process.env.FACTORIO_MOD_PORTAL_URL || DEFAULT_API_BASE,
	};

	for (let i = 0; i < argv.length; i += 1) {
		const arg = argv[i];
		switch (arg) {
			case "--dry-run":
				options.dryRun = true;
				break;
			case "--yes":
			case "-y":
				options.yes = true;
				break;
			case "--keep-archive":
				options.keepArchive = true;
				break;
			case "--allow-dirty":
				options.allowDirty = true;
				break;
			case "--allow-any-branch":
				options.allowAnyBranch = true;
				break;
			case "--skip-version-check":
				options.skipVersionCheck = true;
				break;
			case "--zip":
				if (!argv[i + 1]) {
					throw new Error("--zip requires a path");
				}
				options.zip = argv[++i];
				break;
			case "--api-base":
				if (!argv[i + 1]) {
					throw new Error("--api-base requires a URL");
				}
				options.apiBase = argv[++i];
				break;
			case "-h":
			case "--help":
				options.help = true;
				break;
			default:
				throw new Error(`unknown option '${arg}' (try --help)`);
		}
	}

	options.apiBase = options.apiBase.replace(/\/+$/, "");
	return options;
}

/**
 * Minimal .env reader. Existing environment variables take precedence, which
 * keeps CI secrets usable without writing a .env file.
 */
function loadDotEnv() {
	if (!existsSync(ENV_FILE)) {
		return;
	}

	for (const rawLine of readFileSync(ENV_FILE, "utf8").split(/\r?\n/)) {
		const line = rawLine.trim();
		if (!line || line.startsWith("#")) {
			continue;
		}

		const match = line.match(/^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$/);
		if (!match) {
			continue;
		}

		const name = match[1];
		let value = match[2].trim();
		const quoted =
			(value.startsWith('"') && value.endsWith('"')) ||
			(value.startsWith("'") && value.endsWith("'"));
		if (quoted) {
			value = value.slice(1, -1);
		} else {
			value = value.replace(/\s+#.*$/, "").trim();
		}

		if (!(name in process.env)) {
			process.env[name] = value;
		}
	}
}

function getApiKey() {
	for (const name of API_KEY_VARS) {
		const value = process.env[name];
		if (value && value.trim()) {
			return { name, value: value.trim() };
		}
	}
	return null;
}

async function runGit(args) {
	const { stdout } = await execFileAsync("git", args, {
		cwd: REPO_ROOT,
		encoding: "utf8",
		maxBuffer: 10 * 1024 * 1024,
	});
	return stdout.trim();
}

function readJsonFile(file) {
	return JSON.parse(readFileSync(file, "utf8"));
}

function readTopChangelogEntry(changelog) {
	const lines = changelog.split(/\r?\n/);
	const start = lines.findIndex((line) => /^Version:\s*/.test(line));
	if (start === -1) {
		return null;
	}

	let end = lines.length;
	for (let i = start + 1; i < lines.length; i += 1) {
		if (/^-{10,}\s*$/.test(lines[i])) {
			end = i;
			break;
		}
	}

	const entry = lines.slice(start, end);
	const version = (entry[0].match(/^Version:\s*(.+?)\s*$/) || [])[1] || null;
	const dateLine = entry.find((line) => /^Date:\s*/.test(line));
	const date = dateLine ? dateLine.replace(/^Date:\s*/, "").trim() : null;
	const hasEntries = entry.some((line) => /^\s+-\s+/.test(line));

	return { version, date, hasEntries, text: entry.join("\n") };
}

function validateMetadata(info) {
	if (!info || typeof info !== "object") {
		throw new Error("info.json did not contain an object");
	}
	if (typeof info.name !== "string" || !info.name) {
		throw new Error("info.json is missing a mod name");
	}
	if (typeof info.version !== "string" || !VERSION_PATTERN.test(info.version)) {
		throw new Error(`info.json version is not MAJOR.MINOR.PATCH: '${info.version}'`);
	}

	const changelog = readFileSync(CHANGELOG_FILE, "utf8");
	const entry = readTopChangelogEntry(changelog);
	if (!entry) {
		throw new Error("could not read the newest version from changelog.txt");
	}
	if (entry.version !== info.version) {
		throw new Error(
			`info.json (${info.version}) and changelog.txt (${entry.version}) disagree`
		);
	}
	if (entry.date === "????") {
		console.warn("warning: changelog.txt still has Date: ????; set the release date.");
	}
	if (!entry.hasEntries) {
		console.warn(`warning: changelog.txt entry for ${info.version} has no items.`);
	}
}

async function checkGitState(options) {
	const trackedEnv = (await runGit(["ls-files", ".env"])).trim();
	if (trackedEnv) {
		throw new Error(".env is tracked by git; remove it from the index before publishing");
	}

	const status = await runGit(["status", "--porcelain=v1"]);
	if (status) {
		if (!options.allowDirty) {
			throw new Error(
				"working tree is not clean; commit or stash these changes first " +
					"(or pass --allow-dirty):\n" +
					status
			);
		}
		console.warn("warning: working tree is dirty; the archive will contain HEAD only.");
	}

	const branch = await runGit(["rev-parse", "--abbrev-ref", "HEAD"]);
	if (branch !== "main" && !options.allowAnyBranch) {
		throw new Error(
			`current branch is '${branch}', not 'main' (pass --allow-any-branch to publish anyway)`
		);
	}

	try {
		const counts = (await runGit(["rev-list", "--left-right", "--count", "@{u}...HEAD"]))
			.split(/\s+/)
			.map(Number);
		const [behind, ahead] = counts;
		if (ahead > 0) {
			console.warn(
				`warning: HEAD is ${ahead} commit(s) ahead of its upstream; push before publishing.`
			);
		}
		if (behind > 0) {
			console.warn(`warning: HEAD is ${behind} commit(s) behind its upstream.`);
		}
	} catch {
		// No upstream configured; publishing a local-only branch is allowed.
	}
}

async function parsePortalResponse(response) {
	const raw = await response.text();
	let data = null;
	if (raw) {
		try {
			data = JSON.parse(raw);
		} catch {
			// Keep the raw text for the error message.
		}
	}
	return { ok: response.ok, status: response.status, data, raw };
}

function formatPortalError(result) {
	const data = result.data;
	if (data && typeof data === "object") {
		const parts = [];
		if (data.error) {
			parts.push(String(data.error));
		}
		if (data.message) {
			parts.push(String(data.message));
		}
		if (parts.length > 0) {
			return parts.join(": ");
		}
	}

	const raw = result.raw ? `: ${result.raw.slice(0, 500)}` : "";
	return `HTTP ${result.status} from the mod portal${raw}`;
}

async function checkPublishedVersion(info, options) {
	if (options.skipVersionCheck) {
		return;
	}

	const url = new URL(`/api/mods/${encodeURIComponent(info.name)}/full`, options.apiBase);
	let response;
	try {
		response = await fetch(url, {
			headers: { Accept: "application/json", "User-Agent": USER_AGENT },
		});
	} catch (error) {
		console.warn(`warning: could not check existing releases: ${error.message}`);
		return;
	}

	if (response.status === 404) {
		console.log(`Mod '${info.name}' is not on the portal yet; it will be published as a new mod.`);
		return;
	}

	const result = await parsePortalResponse(response);
	if (!result.ok) {
		console.warn(`warning: could not check existing releases: ${formatPortalError(result)}`);
		return;
	}

	const releases = Array.isArray(result.data?.releases) ? result.data.releases : [];
	if (releases.some((release) => release.version === info.version)) {
		throw new Error(
			`${info.name} ${info.version} is already published on the mod portal. ` +
				"Bump the version before publishing."
		);
	}

	console.log(`Version ${info.version} is not on the portal yet.`);
}

async function buildArchive(info, options) {
	if (options.zip) {
		const zipPath = path.resolve(process.cwd(), options.zip);
		if (!existsSync(zipPath)) {
			throw new Error(`zip file not found: ${zipPath}`);
		}
		return { path: zipPath, generated: false };
	}

	const archiveName = `${info.name}_${info.version}`;
	const zipPath = path.join(REPO_ROOT, `${archiveName}.zip`);
	console.log(`Packaging ${archiveName}.zip from HEAD...`);
	await runGit([
		"archive",
		"--format=zip",
		`--prefix=${archiveName}/`,
		`--output=${zipPath}`,
		"HEAD",
	]);
	return { path: zipPath, generated: true };
}

async function portalFormPost(url, fields, apiKey) {
	let response;
	try {
		response = await fetch(url, {
			method: "POST",
			headers: {
				Accept: "application/json",
				Authorization: `Bearer ${apiKey}`,
				"Content-Type": "application/x-www-form-urlencoded",
				"User-Agent": USER_AGENT,
			},
			body: new URLSearchParams(fields),
		});
	} catch (error) {
		throw new Error(`could not reach the mod portal: ${error.message}`);
	}

	return parsePortalResponse(response);
}

async function initUpload(info, apiKey, apiBase) {
	const initUrl = `${apiBase}/api/v2/mods/releases/init_upload`;
	const init = await portalFormPost(initUrl, { mod: info.name }, apiKey);

	if (init.ok && !init.data?.error) {
		return { uploadUrl: init.data?.upload_url, isNew: false };
	}

	if (init.status === 404 || init.data?.error === "UnknownMod") {
		console.log(`Mod '${info.name}' does not exist yet; creating it on the portal.`);
		const publishUrl = `${apiBase}/api/v2/mods/init_publish`;
		const publish = await portalFormPost(publishUrl, { mod: info.name }, apiKey);
		if (!publish.ok || publish.data?.error) {
			throw new Error(formatPortalError(publish));
		}
		return { uploadUrl: publish.data?.upload_url, isNew: true };
	}

	throw new Error(formatPortalError(init));
}

async function uploadArchive(info, zipPath, apiKey, apiBase) {
	const { uploadUrl, isNew } = await initUpload(info, apiKey, apiBase);
	if (!uploadUrl) {
		throw new Error("the mod portal did not return an upload URL");
	}

	console.log(`Uploading ${path.basename(zipPath)}...`);
	const form = new FormData();
	const buffer = await readFile(zipPath);
	form.append("file", new Blob([buffer], { type: "application/zip" }), path.basename(zipPath));
	if (isNew && info.description) {
		form.append("description", info.description);
	}

	let response;
	try {
		response = await fetch(new URL(uploadUrl, apiBase), {
			method: "POST",
			headers: {
				Accept: "application/json",
				Authorization: `Bearer ${apiKey}`,
				"User-Agent": USER_AGENT,
			},
			body: form,
		});
	} catch (error) {
		throw new Error(`upload failed: ${error.message}`);
	}

	const result = await parsePortalResponse(response);
	if (!result.ok || result.data?.error || result.data?.success !== true) {
		throw new Error(formatPortalError(result));
	}

	return result.data;
}

async function confirmPublish(info, zipPath) {
	const question = `Publish ${info.name} ${info.version} from ${path.basename(zipPath)}? [y/N] `;
	if (!process.stdin.isTTY) {
		throw new Error("refusing to publish non-interactively; pass --yes to confirm");
	}

	const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
	try {
		const answer = await rl.question(question);
		if (!/^y(es)?$/i.test(answer.trim())) {
			throw new Error("publish cancelled");
		}
	} finally {
		rl.close();
	}
}

async function main() {
	const options = parseArgs(process.argv.slice(2));
	if (options.help) {
		process.stdout.write(HELP);
		return;
	}

	loadDotEnv();

	const info = readJsonFile(INFO_FILE);
	validateMetadata(info);

	const apiKey = getApiKey();
	if (!apiKey && !options.dryRun) {
		throw new Error(
			`no API key found. Add FACTORIO_API_KEY=<key> to ${ENV_FILE} ` +
				"(or set FACTORIO_TOKEN / MOD_UPLOAD_API_KEY)."
		);
	}
	if (!apiKey) {
		console.log("No API key found; running as a dry run.");
	}

	if (!options.zip) {
		await checkGitState(options);
	}

	await checkPublishedVersion(info, options);

	const archive = await buildArchive(info, options);
	let succeeded = false;

	try {
		console.log(`Archive: ${archive.path}`);
		console.log(`Mod:     ${info.name}`);
		console.log(`Version: ${info.version}`);

		if (options.dryRun) {
			console.log("Dry run: the archive was built but nothing was uploaded.");
			return;
		}

		if (!options.yes) {
			await confirmPublish(info, archive.path);
		}

		const result = await uploadArchive(info, archive.path, apiKey.value, options.apiBase);
		succeeded = true;
		console.log(`Published ${info.name} ${info.version}.`);
		if (result?.url) {
			console.log(`Portal: ${new URL(result.url, options.apiBase)}`);
		}
	} finally {
		if (archive.generated && succeeded && !options.keepArchive) {
			await rm(archive.path, { force: true });
		} else if (archive.generated && !succeeded) {
			console.log(`Archive kept at ${archive.path}`);
		}
	}
}

main().catch((error) => {
	console.error(`\nerror: ${error.message}`);
	process.exitCode = 1;
});
