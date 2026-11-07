// Android Node build — prerequisite inspection (Node v24 source)
// Purpose: list exactly which gyp/configure patches the Android arm64 build needs
// on this exact Node version, so the CI job can apply a known-good set.
const fs = require('node:fs');
const path = require('node:path');

const root = process.argv[2];
function rd(p) { try { return fs.readFileSync(p, 'utf8'); } catch { return null; } }

const out = { node: {}, gyp: {}, patches: [] };

// 1. Node version
const vh = rd(path.join(root, 'src', 'node_version.h')) || '';
const mm = vh.match(/#define NODE_MAJOR_VERSION (\d+)[\s\S]*?#define NODE_MINOR_VERSION (\d+)[\s\S]*?#define NODE_PATCH_VERSION (\d+)/);
out.node.version = mm ? `${mm[1]}.${mm[2]}.${mm[3]}` : 'unknown';

// 2. android-configure contract
const ac = rd(path.join(root, 'android_configure.py'));
out.androidConfigure = {
  exists: !!ac,
  argvContract: ac ? (ac.match(/if len\(sys\.argv\) != (\d+)/) || [])[1] : null,
  platformGuard: ac ? /currently only supported on Linux and Darwin/.test(ac) : null,
  setsCC_host: ac ? /CC_host|CXX_host/.test(ac) : null
};

// 3. does the build need these known-problem areas?
const commonGypi = rd(path.join(root, 'common.gypi')) || '';
out.gyp.hasLdflagsRead = /'ldflags'/.test(commonGypi);
out.gyp.androidBlocks = (commonGypi.match(/OS\s*==\s*'android'/g) || []).length;

// 4. v8 trap handler (issue 36287) — needs the upstream patch on some versions
const trap = rd(path.join(root, 'deps', 'v8', 'src', 'trap-handler', 'trap-handler.h')) || '';
out.gyp.trapHandlerPresent = !!trap;
out.gyp.trapHandlerHasAndroidGuard = /__ANDROID__/.test(trap);

// 5. uv gyp — android cross builds historically need a patch here
const uvgyp = rd(path.join(root, 'deps', 'uv', 'uv.gyp')) || '';
out.gyp.uvGypPresent = !!uvgyp;

// 6. openssl asm flag support
const cfg = rd(path.join(root, 'configure.py')) || '';
out.gyp.supportsOpensslNoAsm = /openssl-no-asm/.test(cfg);
out.gyp.withIntlDefault = (cfg.match(/--with-intl[\s\S]{0,400}?default='([^']+)'/) || [])[1] || null;
out.gyp.sharedDefault = (cfg.match(/'--shared'[\s\S]{0,200}?default=(\w+)/) || [])[1] || null;
out.gyp.hasLdflagsOption = /--ldflags/.test(cfg);
out.gyp.readsEnvLDFLAGS = /environ\.get\(['"]LDFLAGS/.test(cfg);
out.gyp.readsCC_host = /CC_host/.test(cfg);

console.log(JSON.stringify(out, null, 2));
