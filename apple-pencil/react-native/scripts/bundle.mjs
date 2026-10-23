import {spawnSync} from 'node:child_process';
import {renameSync} from 'node:fs';
const result=spawnSync(process.execPath,['node_modules/metro/src/cli.js','build','index.js','--platform','ios','--dev','false','--minify','false','--out','ios/main.jsbundle'],{stdio:'inherit'});
if(result.status!==0) process.exit(result.status??1);
renameSync('ios/main.jsbundle.js','ios/main.jsbundle');
