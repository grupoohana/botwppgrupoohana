import { createServer } from 'node:http';
import { Readable } from 'node:stream';
import { readFile } from 'node:fs/promises';
import { createApp } from './app.mjs';
const app=createApp();
const files={'/':'index.html','/admin.mjs':'admin.mjs','/style.css':'style.css'};
createServer(async(req,res)=>{
 try{
  if(files[req.url]){const content=await readFile(new URL('../../public/'+files[req.url],import.meta.url));res.writeHead(200,{'content-type':req.url.endsWith('.mjs')?'text/javascript':req.url.endsWith('.css')?'text/css':'text/html','cache-control':'no-store','referrer-policy':'no-referrer','content-security-policy':"default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; base-uri 'none'; frame-ancestors 'none'"});res.end(content);return;}
  const request=new Request('http://localhost:'+app.c.port+req.url,{method:req.method,headers:req.headers,...(!['GET','HEAD'].includes(req.method)?{body:Readable.toWeb(req),duplex:'half'}:{})});
  const result=await app.handler(request);res.writeHead(result.status,Object.fromEntries(result.headers));res.end(Buffer.from(await result.arrayBuffer()));
 }catch{res.writeHead(500);res.end('Internal error');}
}).listen(app.c.port,'127.0.0.1',()=>console.log(`Bot local: http://localhost:${app.c.port}. No se envía a Meta mientras BOT_ENABLED=false.`));
