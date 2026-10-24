#!/usr/bin/env node
/**
 * Regression tests for helper_scripts/publish_mod.mjs.
 *
 * The tests create a temporary git repository, copy the publisher into it, and
 * run it against a loopback mock of the Factorio mod portal. No request leaves
 * the machine and the real repository's .env is never read.
 *
 * Run with: node helper_scripts/test_publish_mod.mjs
 */

import assert from "node:assert/strict";
import { execFile, spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { copyFile, mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { createServer } from "node:http";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);
const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const PUBLISH_SCRIPT = path.join(SCRIPT_DIR, "publish_mod.mjs");

const FIXTURE_NAME = "PlanetsLib";
const FIXTURE_VERSION = "1.2.3";
const FIXTURE_TOKEN = "fixture-token";
const FIXTURE_RELEASE = {
	version: FIXTURE_VERSION,
	file_name: `${FIXTURE_NAME}_${FIXTURE_VERSION}.zip`,
	sha1: "abc123",
	released_at: "2026-10-23T00:00:00Z",
	download_url: "/download/PlanetsLib/fixture",
};

let mock;
let fixture;
const fixtures = [];
const tests = [];

function test(name, fn) {
	tests.push({ name, fn });
}

async function runGit(cwd, args) {
	const { stdout } = await execFileAsync("git", args, {
		cwd,
		encoding: "utf8",
		maxBuffer: 10 * 1024 * 1024,
	});
	return stdout.trim();
}

async function createFixture({ trackedEnvLocal = false } = {}) {
	const root = await mkdtemp(path.join(os.tmpdir(), "planetslib-publish-test-"));
	await mkdir(path.join(root, "helper_scripts"), { recursive: true });
	await mkdir(path.join(root, "test-mods"), { recursive: true });
	await mkdir(path.join(root, ".github", "workflows"), { recursive: true });

	await writeFile(
		path.join(root, "info.json"),
		JSON.stringify(
			{
				name: FIXTURE_NAME,
				version: FIXTURE_VERSION,
				factorio_version: "2.1",
				title: "Fixture",
				author: "Test",
				description: "Fixture mod for publish_mod.mjs tests.",
				dependencies: ["base >= 2.1.22"],
			},
			null,
			2
		) + "\n"
	);

	await writeFile(
		path.join(root, "changelog.txt"),
		[
			"---------------------------------------------------------------------------------------------------",
			`Version: ${FIXTURE_VERSION}`,
			"Date: 2026-10-23",
			"  Bugfixes:",
			"    - Fixture changelog entry.",
			"---------------------------------------------------------------------------------------------------",
			"",
		].join("\n")
	);

	await writeFile(path.join(root, "control.lua"), "-- fixture\n");
	await writeFile(path.join(root, "release.sh"), "#!/bin/sh\n");
	await writeFile(path.join(root, "test-mods", "fixture.txt"), "fixture\n");
	await writeFile(path.join(root, ".github", "workflows", "fixture.yml"), "name: fixture\n");
	await writeFile(
		path.join(root, ".gitignore"),
		[".env", ".env.*", "!.env.example", "*.zip", ""].join("\n")
	);
	await writeFile(
		path.join(root, ".gitattributes"),
		[
			".env export-ignore",
			".env.* export-ignore",
			".gitignore export-ignore",
			".gitattributes export-ignore",
			"helper_scripts export-ignore",
			"test-mods export-ignore",
			".github export-ignore",
			"*.sh export-ignore",
			"",
		].join("\n")
	);
	await writeFile(path.join(root, ".env.example"), "FACTORIO_API_KEY=\n");
	await writeFile(path.join(root, ".env"), `export FACTORIO_API_KEY=${FIXTURE_TOKEN}\n`);
	await copyFile(PUBLISH_SCRIPT, path.join(root, "helper_scripts", "publish_mod.mjs"));

	await runGit(root, ["init", "-b", "main"]);
	await runGit(root, ["config", "user.email", "test@example.com"]);
	await runGit(root, ["config", "user.name", "Publish Test"]);
	if (trackedEnvLocal) {
		await writeFile(path.join(root, ".env.local"), "FACTORIO_API_KEY=tracked\n");
		await runGit(root, ["add", "-f", ".env.local"]);
	}
	await runGit(root, ["add", "-A"]);
	await runGit(root, ["commit", "-m", "fixture"]);

	return root;
}

async function createMockPortal() {
	const state = {
		baseUrl: null,
		validToken: FIXTURE_TOKEN,
		published: [],
		requests: [],
		uploadBody: null,
		uploadAuth: null,
		uploadContentType: null,
	};

	const server = createServer((req, res) => {
		const chunks = [];
		req.on("data", (chunk) => chunks.push(chunk));
		req.on("end", () => {
			const body = Buffer.concat(chunks);
			const url = req.url.split("?")[0];
			const auth = req.headers.authorization || "";
			state.requests.push({ method: req.method, url, auth, body });

			if (req.method === "GET" && url === `/api/mods/${FIXTURE_NAME}/full`) {
				res.writeHead(200, {
					"Content-Type": "application/json",
					"Cache-Control": "no-store",
				});
				res.end(JSON.stringify({ releases: state.published }));
				return;
			}

			if (req.method === "POST" && url === "/api/v2/mods/edit_details") {
				if (auth !== `Bearer ${state.validToken}`) {
					res.writeHead(403, { "Content-Type": "application/json" });
					res.end(JSON.stringify({ error: "InvalidApiKey" }));
					return;
				}
				const params = new URLSearchParams(body.toString("utf8"));
				if (params.get("mod") !== FIXTURE_NAME) {
					res.writeHead(400, { "Content-Type": "application/json" });
					res.end(JSON.stringify({ error: "InvalidRequest", message: "bad mod" }));
					return;
				}
				res.writeHead(200, { "Content-Type": "application/json" });
				res.end(JSON.stringify({ success: true }));
				return;
			}

			if (req.method === "POST" && url === "/api/v2/mods/releases/init_upload") {
				if (auth !== `Bearer ${state.validToken}`) {
					res.writeHead(403, { "Content-Type": "application/json" });
					res.end(JSON.stringify({ error: "InvalidApiKey" }));
					return;
				}
				const params = new URLSearchParams(body.toString("utf8"));
				if (params.get("mod") !== FIXTURE_NAME) {
					res.writeHead(400, { "Content-Type": "application/json" });
					res.end(JSON.stringify({ error: "InvalidRequest", message: "bad mod" }));
					return;
				}
				res.writeHead(200, { "Content-Type": "application/json" });
				res.end(JSON.stringify({ upload_url: `${state.baseUrl}/upload` }));
				return;
			}

			if (req.method === "POST" && url === "/upload") {
				if (auth !== `Bearer ${state.validToken}`) {
					res.writeHead(403, { "Content-Type": "application/json" });
					res.end(JSON.stringify({ error: "InvalidApiKey" }));
					return;
				}
				state.uploadAuth = auth;
				state.uploadBody = body;
				state.uploadContentType = req.headers["content-type"] || "";
				res.writeHead(200, { "Content-Type": "application/json" });
				res.end(JSON.stringify({ success: true, url: `/api/mods/${FIXTURE_NAME}` }));
				return;
			}

			res.writeHead(404, { "Content-Type": "application/json" });
			res.end(JSON.stringify({ error: "NotFound" }));
		});
	});

	await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
	state.baseUrl = `http://127.0.0.1:${server.address().port}`;

	return {
		state,
		close: () =>
			new Promise((resolve) => {
				server.close(() => resolve());
				if (typeof server.closeAllConnections === "function") {
					server.closeAllConnections();
				}
			}),
		reset() {
			state.published = [];
			state.requests = [];
			state.uploadBody = null;
			state.uploadAuth = null;
			state.uploadContentType = null;
			state.validToken = FIXTURE_TOKEN;
		},
	};
}

function runPublisher(root, args, extraEnv = {}) {
	const env = { ...process.env };
	delete env.FACTORIO_API_KEY;
	delete env.FACTORIO_TOKEN;
	delete env.MOD_UPLOAD_API_KEY;
	delete env.FACTORIO_MOD_PORTAL_URL;
	Object.assign(env, extraEnv);

	return new Promise((resolve, reject) => {
		const child = spawn(
			process.execPath,
			[path.join(root, "helper_scripts", "publish_mod.mjs"), ...args],
			{ cwd: root, env }
		);
		let stdout = "";
		let stderr = "";
		let timedOut = false;
		const timer = setTimeout(() => {
			timedOut = true;
			child.kill("SIGKILL");
		}, 30000);

		child.stdout.on("data", (chunk) => {
			stdout += chunk;
		});
		child.stderr.on("data", (chunk) => {
			stderr += chunk;
		});
		child.on("error", (error) => {
			clearTimeout(timer);
			reject(error);
		});
		child.on("close", (code) => {
			clearTimeout(timer);
			if (timedOut) {
				reject(new Error(`publisher timed out after 30s: ${args.join(" ")}`));
				return;
			}
			resolve({ code, stdout, stderr });
		});
	});
}

function listZipEntries(buffer) {
	const eocdSignature = 0x06054b50;
	let eocd = -1;
	for (let i = buffer.length - 22; i >= 0; i -= 1) {
		if (buffer.readUInt32LE(i) === eocdSignature) {
			eocd = i;
			break;
		}
	}
	if (eocd === -1) {
		throw new Error("ZIP end-of-central-directory record not found");
	}

	const entryCount = buffer.readUInt16LE(eocd + 10);
	let offset = buffer.readUInt32LE(eocd + 16);
	const entries = [];
	for (let i = 0; i < entryCount; i += 1) {
		if (buffer.readUInt32LE(offset) !== 0x02014b50) {
			throw new Error(`bad central directory header at ${offset}`);
		}
		const nameLength = buffer.readUInt16LE(offset + 28);
		const extraLength = buffer.readUInt16LE(offset + 30);
		const commentLength = buffer.readUInt16LE(offset + 32);
		const name = buffer
			.subarray(offset + 46, offset + 46 + nameLength)
			.toString("utf8");
		entries.push(name);
		offset += 46 + nameLength + extraLength + commentLength;
	}
	return entries;
}

function assertNoKeyLeak(result, key) {
	assert.ok(!result.stdout.includes(key), "stdout must not contain the API key");
	assert.ok(!result.stderr.includes(key), "stderr must not contain the API key");
}

test("uploads the committed version and excludes development files", async () => {
	mock.reset();
	const zipPath = path.join(fixture, `${FIXTURE_NAME}_${FIXTURE_VERSION}.zip`);
	await rm(zipPath, { force: true });

	const result = await runPublisher(fixture, [
		"--api-base",
		mock.state.baseUrl,
		"--yes",
		"--keep-archive",
	]);
	assert.equal(result.code, 0, result.stderr);
	assert.match(result.stdout, /Published PlanetsLib 1\.2\.3\./);
	assertNoKeyLeak(result, FIXTURE_TOKEN);

	const initRequests = mock.state.requests.filter(
		(request) => request.url === "/api/v2/mods/releases/init_upload"
	);
	assert.equal(initRequests.length, 1);
	assert.equal(initRequests[0].auth, `Bearer ${FIXTURE_TOKEN}`);
	assert.equal(
		new URLSearchParams(initRequests[0].body.toString("utf8")).get("mod"),
		FIXTURE_NAME
	);

	assert.equal(mock.state.uploadAuth, `Bearer ${FIXTURE_TOKEN}`);
	assert.match(mock.state.uploadContentType, /^multipart\/form-data; boundary=/);
	assert.ok(mock.state.uploadBody.includes(Buffer.from('name="file"')));
	assert.ok(
		mock.state.uploadBody.includes(
			Buffer.from(`filename="${FIXTURE_NAME}_${FIXTURE_VERSION}.zip"`)
		)
	);
	assert.ok(mock.state.uploadBody.includes(Buffer.from("PK")));

	assert.ok(existsSync(zipPath), "the kept archive should exist");
	const entries = listZipEntries(await readFile(zipPath));
	assert.ok(entries.includes(`PlanetsLib_${FIXTURE_VERSION}/info.json`));
	assert.ok(entries.includes(`PlanetsLib_${FIXTURE_VERSION}/changelog.txt`));
	assert.ok(entries.includes(`PlanetsLib_${FIXTURE_VERSION}/control.lua`));
	for (const forbidden of [
		".env",
		".env.example",
		".gitignore",
		".gitattributes",
		"helper_scripts/",
		"test-mods/",
		".github/",
		"release.sh",
	]) {
		assert.ok(
			!entries.some((entry) => entry.includes(forbidden)),
			`archive must not contain ${forbidden}`
		);
	}
});

test("rejects a version already published on the portal", async () => {
	mock.reset();
	mock.state.published = [FIXTURE_RELEASE];

	const result = await runPublisher(fixture, [
		"--api-base",
		mock.state.baseUrl,
		"--yes",
	]);
	assert.notEqual(result.code, 0);
	assert.match(result.stderr, /already published/);
	assert.equal(
		mock.state.requests.filter(
			(request) => request.url === "/api/v2/mods/releases/init_upload"
		).length,
		0
	);
});

test("rejects tracked .env.local files", async () => {
	mock.reset();
	const trackedFixture = await createFixture({ trackedEnvLocal: true });
	fixtures.push(trackedFixture);

	const result = await runPublisher(trackedFixture, [
		"--api-base",
		mock.state.baseUrl,
		"--dry-run",
	]);
	assert.notEqual(result.code, 0);
	assert.match(result.stderr, /environment file\(s\) are tracked/);
	assert.match(result.stderr, /\.env\.local/);
	assert.equal(mock.state.requests.length, 0);
});

test("validates the API key without uploading", async () => {
	mock.reset();
	const result = await runPublisher(fixture, [
		"--api-base",
		mock.state.baseUrl,
		"--dry-run",
		"--check-key",
	]);
	assert.equal(result.code, 0, result.stderr);
	assert.match(result.stdout, /API key FACTORIO_API_KEY is valid\./);
	assertNoKeyLeak(result, FIXTURE_TOKEN);

	const requests = mock.state.requests.filter(
		(request) => request.url === "/api/v2/mods/edit_details"
	);
	assert.equal(requests.length, 1);
	assert.equal(requests[0].auth, `Bearer ${FIXTURE_TOKEN}`);
	assert.equal(
		new URLSearchParams(requests[0].body.toString("utf8")).get("mod"),
		FIXTURE_NAME
	);
	assert.equal(
		mock.state.requests.filter(
			(request) => request.url === "/api/v2/mods/releases/init_upload"
		).length,
		0
	);
	assert.equal(
		mock.state.requests.filter((request) => request.url === "/upload").length,
		0
	);
});

test("rejects an invalid API key in --check-key mode", async () => {
	mock.reset();
	const result = await runPublisher(
		fixture,
		["--api-base", mock.state.baseUrl, "--check-key"],
		{ FACTORIO_API_KEY: "bad-token" }
	);
	assert.notEqual(result.code, 0);
	assert.match(result.stderr, /InvalidApiKey/);
	assertNoKeyLeak(result, "bad-token");
	assert.equal(
		mock.state.requests.filter(
			(request) => request.url === "/api/v2/mods/edit_details"
		).length,
		1
	);
});

test("verifies a published release", async () => {
	mock.reset();
	mock.state.published = [FIXTURE_RELEASE];

	const result = await runPublisher(fixture, [
		"--api-base",
		mock.state.baseUrl,
		"--verify",
	]);
	assert.equal(result.code, 0, result.stderr);
	assert.match(result.stdout, /Verified PlanetsLib 1\.2\.3/);
	assert.match(result.stdout, /file:\s+PlanetsLib_1\.2\.3\.zip/);
	assert.match(result.stdout, /sha1:\s+abc123/);
	assert.match(result.stdout, /released_at:\s+2026-10-23T00:00:00Z/);
});

test("fails verification when the version is absent", async () => {
	mock.reset();
	const result = await runPublisher(fixture, [
		"--api-base",
		mock.state.baseUrl,
		"--verify",
	]);
	assert.notEqual(result.code, 0);
	assert.match(result.stderr, /not on the portal yet/);
});

test("keeps the generated archive during a dry run", async () => {
	mock.reset();
	const zipPath = path.join(fixture, `${FIXTURE_NAME}_${FIXTURE_VERSION}.zip`);
	await rm(zipPath, { force: true });

	const result = await runPublisher(fixture, [
		"--api-base",
		mock.state.baseUrl,
		"--dry-run",
	]);
	assert.equal(result.code, 0, result.stderr);
	assert.match(result.stdout, /Dry run/);
	assert.ok(existsSync(zipPath), "dry run should keep the archive");
	assert.equal(
		mock.state.requests.filter((request) => request.url === "/upload").length,
		0
	);
});

async function main() {
	mock = await createMockPortal();
	let failures = 0;

	try {
		fixture = await createFixture();
		fixtures.push(fixture);

		for (const { name, fn } of tests) {
			try {
				await fn();
				console.log(`PASS ${name}`);
			} catch (error) {
				failures += 1;
				console.error(`FAIL ${name}`);
				console.error(error.stack || error);
			}
		}
	} finally {
		await mock.close();
		await Promise.all(
			fixtures.map((directory) => rm(directory, { recursive: true, force: true }))
		);
	}

	if (failures > 0) {
		console.error(`${failures} test(s) failed`);
		process.exitCode = 1;
	} else {
		console.log(`${tests.length} tests passed`);
	}
}

main().catch((error) => {
	console.error(error.stack || error);
	process.exitCode = 1;
});
