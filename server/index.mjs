import {createApp} from './app.mjs';
const port=Number(process.env.API_PORT||3001),host=process.env.HOST||'127.0.0.1';
const origins=(process.env.ALLOWED_ORIGINS||'http://localhost:5173,http://127.0.0.1:5173').split(',');
const app=createApp({dbPath:process.env.DATABASE_PATH||'.data/krishi.sqlite',origins,serveStatic:process.env.NODE_ENV==='production',trustProxy:process.env.TRUST_PROXY==='true'});
app.server.listen(port,host,()=>console.log(`Krishi Saathi API listening at http://${host}:${port}`));
for(const signal of ['SIGINT','SIGTERM'])process.on(signal,async()=>{await app.close();process.exit(0);});
