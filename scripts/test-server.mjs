import {scryptSync} from 'node:crypto';
import {createApp} from '../server/app.mjs';
const app=createApp({serveStatic:true,origins:['http://127.0.0.1:5180']});
app.db.prepare('INSERT INTO admins(name,phone,password,salt) VALUES(?,?,?,?)').run('KVK Test Admin','9333333333',scryptSync('Temporary-admin-123','test-salt',64).toString('hex'),'test-salt');
app.server.listen(5180,'127.0.0.1',()=>console.log('Browser test server ready'));
for(const sig of ['SIGINT','SIGTERM'])process.on(sig,async()=>{await app.close();process.exit(0);});
