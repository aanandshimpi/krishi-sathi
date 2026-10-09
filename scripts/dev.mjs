import {spawn} from 'node:child_process';
const commands=[['server/index.mjs'],['node_modules/vite/bin/vite.js','--host','0.0.0.0']];
const children=commands.map(args=>spawn(process.execPath,args,{stdio:'inherit',env:process.env}));
let exiting=false;
function stop(code=0){if(exiting)return;exiting=true;for(const child of children)child.kill('SIGTERM');process.exitCode=code;}
for(const child of children)child.on('exit',code=>stop(code||0));
process.on('SIGINT',()=>stop());process.on('SIGTERM',()=>stop());
