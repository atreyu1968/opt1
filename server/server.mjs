import http from 'node:http';
import { DatabaseSync } from 'node:sqlite';
import { randomBytes, scryptSync, timingSafeEqual, createHash } from 'node:crypto';
import { mkdirSync, readFileSync, existsSync, statSync, createReadStream } from 'node:fs';
import { join, extname, resolve, normalize } from 'node:path';

function loadEnv(file){if(!existsSync(file))return;for(const line of readFileSync(file,'utf8').split(/\r?\n/)){if(!line||line.trim().startsWith('#')||!line.includes('='))continue;const i=line.indexOf('=');const k=line.slice(0,i).trim(),v=line.slice(i+1).trim();if(!(k in process.env))process.env[k]=v;}}
loadEnv(join(import.meta.dirname,'.env'));
const PORT=Number(process.env.PORT||8080),HOST=process.env.HOST||'0.0.0.0';
const DATA_DIR=process.env.DATA_DIR||join(import.meta.dirname,'data');mkdirSync(DATA_DIR,{recursive:true});
const WEB_DIR=resolve(import.meta.dirname,'../web');
const origins=(process.env.PUBLIC_ORIGINS||'').split(',').map(x=>x.trim()).filter(Boolean);
const sessionMs=Number(process.env.SESSION_HOURS||168)*3600000;
const db=new DatabaseSync(join(DATA_DIR,'opt1.sqlite'));
db.exec(`PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;
CREATE TABLE IF NOT EXISTS admins(id INTEGER PRIMARY KEY, username TEXT UNIQUE NOT NULL, password_hash TEXT NOT NULL, created_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS students(id INTEGER PRIMARY KEY, code TEXT UNIQUE NOT NULL, first_name TEXT NOT NULL, last_name TEXT NOT NULL, group_name TEXT NOT NULL, pin_hash TEXT NOT NULL, active INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL, last_login TEXT);
CREATE TABLE IF NOT EXISTS sessions(id INTEGER PRIMARY KEY, token_hash TEXT UNIQUE NOT NULL, role TEXT NOT NULL, user_id INTEGER NOT NULL, expires_at INTEGER NOT NULL, created_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS progress(id INTEGER PRIMARY KEY, student_id INTEGER NOT NULL, course_id TEXT NOT NULL, course_version TEXT, state_json TEXT NOT NULL, score REAL NOT NULL DEFAULT 0, status TEXT NOT NULL DEFAULT 'incomplete', updated_at TEXT NOT NULL, UNIQUE(student_id,course_id), FOREIGN KEY(student_id) REFERENCES students(id) ON DELETE CASCADE);`);

const attempts=new Map();
function limited(ip){const now=Date.now(),v=attempts.get(ip)||[];const fresh=v.filter(t=>now-t<60000);fresh.push(now);attempts.set(ip,fresh);return fresh.length>40;}
function hashSecret(secret){const salt=randomBytes(16).toString('hex');return salt+':'+scryptSync(secret,salt,32).toString('hex');}
function verifySecret(secret,stored){try{const [salt,hex]=stored.split(':');return timingSafeEqual(scryptSync(secret,salt,32),Buffer.from(hex,'hex'));}catch{return false;}}
function tokenHash(t){return createHash('sha256').update(t).digest('hex');}
function issueSession(role,userId){const token=randomBytes(32).toString('base64url'),now=new Date().toISOString();db.prepare('INSERT INTO sessions(token_hash,role,user_id,expires_at,created_at) VALUES(?,?,?,?,?)').run(tokenHash(token),role,userId,Date.now()+sessionMs,now);return token;}
function auth(req,role){const raw=(req.headers.authorization||'').replace(/^Bearer\s+/i,'');if(!raw)return null;const s=db.prepare('SELECT * FROM sessions WHERE token_hash=? AND expires_at>?').get(tokenHash(raw),Date.now());if(!s||role&&s.role!==role)return null;return s;}
function clean(v,max=100){return String(v||'').trim().replace(/[<>]/g,'').slice(0,max);}
function studentCode(){let c;do{c='OPT-'+randomBytes(4).toString('hex').slice(0,6).toUpperCase();}while(db.prepare('SELECT 1 FROM students WHERE code=?').get(c));return c;}
function profileStudent(s){return{id:s.id,code:s.code,firstName:s.first_name,lastName:s.last_name,group:s.group_name};}
function cors(req,res){const o=req.headers.origin||'';if(o&&origins.includes(o)){res.setHeader('Access-Control-Allow-Origin',o);res.setHeader('Vary','Origin');}res.setHeader('Access-Control-Allow-Headers','Content-Type, Authorization');res.setHeader('Access-Control-Allow-Methods','GET,POST,PUT,OPTIONS');res.setHeader('X-Content-Type-Options','nosniff');res.setHeader('Referrer-Policy','no-referrer');res.setHeader('Permissions-Policy','camera=(), microphone=(), geolocation=()');}
function json(res,status,data){res.writeHead(status,{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store'});res.end(JSON.stringify(data));}
async function body(req){let s='';for await(const c of req){s+=c;if(s.length>50000)throw new Error('Solicitud demasiado grande');}return s?JSON.parse(s):{};}
function routeMatch(path,pattern){const a=path.split('/').filter(Boolean),b=pattern.split('/').filter(Boolean);if(a.length!==b.length)return null;const p={};for(let i=0;i<b.length;i++){if(b[i].startsWith(':'))p[b[i].slice(1)]=decodeURIComponent(a[i]);else if(a[i]!==b[i])return null;}return p;}

async function api(req,res,url){
  if(req.method==='GET'&&url.pathname==='/api/health')return json(res,200,{ok:true,service:'opt1',time:new Date().toISOString()});
  if(req.method==='GET'&&url.pathname==='/api/setup-status')return json(res,200,{needsSetup:!db.prepare('SELECT 1 FROM admins LIMIT 1').get()});
  if(req.method==='POST'&&url.pathname==='/api/setup'){
    if(db.prepare('SELECT 1 FROM admins LIMIT 1').get())return json(res,409,{error:'El administrador ya está configurado.'});
    const d=await body(req),username=clean(d.username,60),password=String(d.password||'');if(username.length<3||password.length<10)return json(res,400,{error:'Use un usuario de 3 caracteres y una contraseña de al menos 10 caracteres.'});
    const r=db.prepare('INSERT INTO admins(username,password_hash,created_at) VALUES(?,?,?)').run(username,hashSecret(password),new Date().toISOString());return json(res,201,{ok:true,token:issueSession('admin',Number(r.lastInsertRowid)),profile:{role:'admin',username}});
  }
  if(req.method==='POST'&&url.pathname==='/api/student/register'){
    const d=await body(req),first=clean(d.firstName,60),last=clean(d.lastName,100),group=clean(d.group,60),pin=String(d.pin||'');if(first.length<2||last.length<2||group.length<1||!/^[0-9]{4,8}$/.test(pin))return json(res,400,{error:'Revisa nombre, apellidos, grupo y PIN de 4 a 8 cifras.'});
    const code=studentCode(),r=db.prepare('INSERT INTO students(code,first_name,last_name,group_name,pin_hash,created_at) VALUES(?,?,?,?,?,?)').run(code,first,last,group,hashSecret(pin),new Date().toISOString());const id=Number(r.lastInsertRowid);return json(res,201,{token:issueSession('student',id),profile:{id,code,firstName:first,lastName:last,group}});
  }
  if(req.method==='POST'&&url.pathname==='/api/login'){
    const d=await body(req);if(d.role==='admin'){const u=db.prepare('SELECT * FROM admins WHERE username=?').get(clean(d.username,60));if(!u||!verifySecret(String(d.password||''),u.password_hash))return json(res,401,{error:'Credenciales incorrectas.'});return json(res,200,{token:issueSession('admin',u.id),profile:{role:'admin',username:u.username}});}
    const s=db.prepare('SELECT * FROM students WHERE code=? AND active=1').get(clean(d.code,20).toUpperCase());if(!s||!verifySecret(String(d.pin||''),s.pin_hash))return json(res,401,{error:'Código o PIN incorrectos.'});db.prepare('UPDATE students SET last_login=? WHERE id=?').run(new Date().toISOString(),s.id);return json(res,200,{token:issueSession('student',s.id),profile:profileStudent(s)});
  }
  if(req.method==='GET'&&url.pathname==='/api/me'){const s=auth(req);if(!s)return json(res,401,{error:'Sesión no válida.'});if(s.role==='student'){const u=db.prepare('SELECT * FROM students WHERE id=?').get(s.user_id);return json(res,200,{profile:profileStudent(u)});}const a=db.prepare('SELECT username FROM admins WHERE id=?').get(s.user_id);return json(res,200,{profile:{role:'admin',username:a.username}});}
  if(req.method==='GET'&&url.pathname==='/api/progress'){const s=auth(req,'student');if(!s)return json(res,401,{error:'Sesión no válida.'});const course=clean(url.searchParams.get('courseId'),80),p=db.prepare('SELECT * FROM progress WHERE student_id=? AND course_id=?').get(s.user_id,course);return json(res,200,p?{state:JSON.parse(p.state_json),score:p.score,status:p.status,updatedAt:p.updated_at}:{state:null,score:0,status:'not-started'});}
  if(req.method==='PUT'&&url.pathname==='/api/progress'){const s=auth(req,'student');if(!s)return json(res,401,{error:'Sesión no válida.'});const d=await body(req),course=clean(d.courseId,80),version=clean(d.version,30),status=['incomplete','passed','failed'].includes(d.status)?d.status:'incomplete',score=Math.max(0,Math.min(100,Number(d.score)||0)),raw=JSON.stringify(d.state||{});if(!course||raw.length>30000)return json(res,400,{error:'Progreso no válido.'});const now=new Date().toISOString();db.prepare(`INSERT INTO progress(student_id,course_id,course_version,state_json,score,status,updated_at) VALUES(?,?,?,?,?,?,?) ON CONFLICT(student_id,course_id) DO UPDATE SET course_version=excluded.course_version,state_json=excluded.state_json,score=excluded.score,status=excluded.status,updated_at=excluded.updated_at`).run(s.user_id,course,version,raw,score,status,now);return json(res,200,{ok:true,updatedAt:now});}
  if(req.method==='GET'&&url.pathname==='/api/admin/students'){const a=auth(req,'admin');if(!a)return json(res,401,{error:'Acceso de administración requerido.'});const rows=db.prepare(`SELECT s.id,s.code,s.first_name AS firstName,s.last_name AS lastName,s.group_name AS groupName,s.active,s.created_at AS createdAt,s.last_login AS lastLogin,p.score,p.status,p.updated_at AS progressUpdated FROM students s LEFT JOIN progress p ON p.student_id=s.id AND p.course_id='opt1-ud1' ORDER BY s.group_name,s.last_name,s.first_name`).all();return json(res,200,{students:rows});}
  if(req.method==='POST'&&routeMatch(url.pathname,'/api/admin/students/:id/reset-pin')){const a=auth(req,'admin');if(!a)return json(res,401,{error:'Acceso de administración requerido.'});const p=routeMatch(url.pathname,'/api/admin/students/:id/reset-pin'),d=await body(req),pin=String(d.pin||'1234');if(!/^[0-9]{4,8}$/.test(pin))return json(res,400,{error:'El PIN debe tener entre 4 y 8 cifras.'});db.prepare('UPDATE students SET pin_hash=? WHERE id=?').run(hashSecret(pin),Number(p.id));return json(res,200,{ok:true});}
  if(req.method==='GET'&&url.pathname==='/api/admin/export.csv'){const a=auth(req,'admin');if(!a)return json(res,401,{error:'Acceso de administración requerido.'});const rows=db.prepare(`SELECT s.code,s.first_name,s.last_name,s.group_name,p.score,p.status,p.updated_at FROM students s LEFT JOIN progress p ON p.student_id=s.id AND p.course_id='opt1-ud1' ORDER BY s.group_name,s.last_name`).all();const esc=v=>'"'+String(v??'').replaceAll('"','""')+'"';const csv='Código,Nombre,Apellidos,Grupo,Puntuación,Estado,Última actualización\n'+rows.map(r=>[r.code,r.first_name,r.last_name,r.group_name,r.score,r.status,r.updated_at].map(esc).join(',')).join('\n');res.writeHead(200,{'Content-Type':'text/csv; charset=utf-8','Content-Disposition':'attachment; filename="progreso-opt1.csv"'});return res.end('\ufeff'+csv);}
  return json(res,404,{error:'Ruta no encontrada.'});
}

function staticFile(req,res,url){let p=url.pathname==='/'?'/index.html':url.pathname;if(p.includes('..'))return json(res,400,{error:'Ruta no válida.'});const file=join(WEB_DIR,normalize(p));if(!file.startsWith(WEB_DIR)||!existsSync(file)||!statSync(file).isFile())return false;const types={'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.css':'text/css; charset=utf-8','.xml':'application/xml; charset=utf-8'};res.writeHead(200,{'Content-Type':types[extname(file)]||'application/octet-stream','Cache-Control':extname(file)==='.html'?'no-cache':'public,max-age=3600'});createReadStream(file).pipe(res);return true;}
const server=http.createServer(async(req,res)=>{cors(req,res);if(req.method==='OPTIONS'){res.writeHead(204);return res.end();}const ip=req.socket.remoteAddress||'unknown';if(limited(ip))return json(res,429,{error:'Demasiadas solicitudes. Espera un minuto.'});const url=new URL(req.url,'http://localhost');try{if(url.pathname.startsWith('/api/'))return await api(req,res,url);if(!staticFile(req,res,url))json(res,404,{error:'Archivo no encontrado.'});}catch(e){console.error(e);json(res,500,{error:'Error interno del servidor.'});}});
server.listen(PORT,HOST,()=>console.log(`OPT1 disponible en http://${HOST}:${PORT}`));
