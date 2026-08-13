#!/usr/bin/env node
/*
 * 版本号同步脚本（Flutter 版）
 * 版本号唯一来源：pubspec.yaml 的 version 字段
 * 脚本同步 lib/data/app_data.dart（AppData.version）
 * 命名：npm run sync-version 或 node scripts/sync-version.js
 */
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const PUBSPEC = path.join(ROOT, 'pubspec.yaml');
const APP_DATA = path.join(ROOT, 'lib', 'data', 'app_data.dart');

function readPubspecVersion() {
  const text = fs.readFileSync(PUBSPEC, 'utf8');
  const m = text.match(/^version:\s*([0-9]+\.[0-9]+\.[0-9]+)(?:\+[0-9]+)?\s*$/m);
  if (!m) throw new Error('pubspec.yaml 中找不到 version 字段');
  return m[1];
}

function syncAppData(version) {
  let text = fs.readFileSync(APP_DATA, 'utf8');
  const re = /(static const String version = ")[0-9]+\.[0-9]+\.[0-9]+(")/;
  if (!re.test(text)) throw new Error('app_data.dart 中找不到 AppData.version');
  text = text.replace(re, `$1${version}$2`);
  fs.writeFileSync(APP_DATA, text);
  console.log(`✔ 已同步 app_data.dart → ${version}`);
}

function main() {
  const version = readPubspecVersion();
  console.log(`当前版本号（pubspec.yaml）：${version}`);
  syncAppData(version);
  console.log('✔ 全部同步完成');
}

main();
