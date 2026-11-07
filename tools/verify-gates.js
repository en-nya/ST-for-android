// Local verification of the CI gate logic, using fixtures captured from a REAL
// NDK r28c build so we know what readelf output actually looks like.
//
// Run: node tools/verify-gates.js
//
// These fixtures came from `llvm-readelf -lW` on an aarch64-linux-android26 binary
// built with NDK 28.2.13676358 (see docs/02-sds.md §2.1/§2.2).

const GOOD = [
  '  LOAD           0x000000 0x0000000000000000 0x0000000000000000 0x000648 0x000648 R   0x4000',
  '  LOAD           0x000648 0x0000000000004648 0x0000000000004648 0x000188 0x000188 R E 0x4000',
  '  LOAD           0x0007d0 0x00000000000087d0 0x00000000000087d0 0x0001b0 0x000830 RW  0x4000',
  '  LOAD           0x000980 0x000000000000c980 0x000000000000c980 0x000018 0x000020 RW  0x4000',
];

// 4 KB aligned (the pre-NDK-r28 default) — must be rejected for Play / Android 15+.
const BAD_ALIGN = [
  '  LOAD           0x000000 0x0000000000000000 0x0000000000000000 0x000648 0x000648 R   0x1000',
];

// 16 KB declared but NOT congruent — a subtler failure some patched linkers emit.
const BAD_CONGRUENT = [
  '  LOAD           0x000100 0x0000000000000000 0x0000000000000000 0x000648 0x000648 R   0x4000',
];

// A shared object (e_entry == 0) must be rejected: that is the fogtape/nodejs-mobile
// class of artifact, which cannot be execve'd from an APK.
const BAD_ENTRY = '  Entry point address:               0x0';

function checkLoads(lines) {
  const problems = [];
  if (lines.length === 0) problems.push('no PT_LOAD segments');
  for (const line of lines) {
    const t = line.trim().split(/\s+/);
    const align = t[t.length - 1];
    const off = t[1];
    const va = t[2];
    const ai = parseInt(align, 16);
    const oi = parseInt(off, 16);
    const vi = parseInt(va, 16);
    if (ai !== 16384) problems.push(`p_align=0x${ai.toString(16)} (expected 0x4000) in: ${line.trim()}`);
    if ((vi - oi) % 16384 !== 0) problems.push(`(vaddr-offset)%16384=${(vi - oi) % 16384} in: ${line.trim()}`);
  }
  return problems;
}

function checkEntry(line) {
  const m = line.match(/0x([0-9a-fA-F]+)/);
  if (!m) return ['cannot parse entry point'];
  return parseInt(m[1], 16) === 0
    ? ['e_entry == 0 -> ET_DYN shared object, NOT an executable (execve would ENOEXEC)']
    : [];
}

let failures = 0;
function expect(name, problems, wantFail) {
  const failed = problems.length > 0;
  const ok = failed === wantFail;
  if (!ok) failures++;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name.padEnd(46)} problems=${problems.length} expected=${wantFail ? 'reject' : 'accept'}`);
  if (!ok) problems.forEach(p => console.log(`        ${p}`));
}

expect('16KB-aligned executable (NDK r28 real output)', checkLoads(GOOD), false);
expect('4KB-aligned (must be rejected)',                checkLoads(BAD_ALIGN), true);
expect('16KB but non-congruent (must be rejected)',      checkLoads(BAD_CONGRUENT), true);
expect('empty segment list (must be rejected)',          checkLoads([]), true);
expect('e_entry != 0 (real executable)',                 checkEntry('  Entry point address:               0x4648'), false);
expect('e_entry == 0 (shared lib, must be rejected)',    checkEntry(BAD_ENTRY), true);

console.log(`\n${failures === 0 ? 'ALL GATE LOGIC VERIFIED' : failures + ' FAILURE(S)'}`);
process.exit(failures === 0 ? 0 : 1);
