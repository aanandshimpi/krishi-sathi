import {defineConfig} from 'vite';
export default defineConfig({
  plugins:[{name:'admin-route',configureServer(server){server.middlewares.use((req,_res,next)=>{if(req.url==='/admin'||req.url==='/admin/')req.url='/admin.html';next();});}}],
  build:{rollupOptions:{input:{main:'index.html',admin:'admin.html'}}},
  server:{watch:{ignored:['**/.tooling/**','**/mobile/**','**/.data/**','**/artifacts/**']},proxy:{'/api':'http://127.0.0.1:3001'}}
});
