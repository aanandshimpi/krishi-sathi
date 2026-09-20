import { createServer } from 'node:http';
import { DatabaseSync } from 'node:sqlite';
import { randomBytes, createHash, scrypt, timingSafeEqual } from 'node:crypto';
import { promisify } from 'node:util';
import { mkdirSync, chmodSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import { resolve, extname, dirname } from 'node:path';
import { createOtpService } from './otp.mjs';
const derive = promisify(scrypt);
const hash = value => createHash('sha256').update(value).digest('hex');
const publicUser = u => ({ id:u.id, name:u.name, phone:u.phone, age:u.age, role:u.role, address:u.address, lat:u.lat, lng:u.lng, ...(u.role==='admin'?{mustChangePassword:!!u.must_change}:{}) });
export const today = () => new Intl.DateTimeFormat('en-CA', {timeZone:'Asia/Kolkata',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
export function distanceKm(a,b,c,d) { const r=x=>x*Math.PI/180; const h=Math.sin(r(c-a)/2)**2+Math.cos(r(a))*Math.cos(r(c))*Math.sin(r(d-b)/2)**2; return 6371*2*Math.atan2(Math.sqrt(h),Math.sqrt(1-h)); }
function fail(status,message){ throw Object.assign(new Error(message),{status}); }
function text(value,name,min=1,max=150){ if(typeof value!=='string'||value.trim().length<min||value.trim().length>max)fail(400,`${name} must contain ${min}–${max} characters.`);return value.trim(); }
function number(value,name,min,max){ if(typeof value!=='number'||!Number.isFinite(value)||value<min||value>max)fail(400,`${name} must be between ${min} and ${max}.`);return value; }
function integer(value,name,min,max){number(value,name,min,max);if(!Number.isInteger(value))fail(400,`${name} must be a whole number.`);return value;}
function coordinates(body,required=false){ if(body.lat==null&&body.lng==null&&!required)return {lat:null,lng:null};return {lat:number(body.lat,'Latitude',-90,90),lng:number(body.lng,'Longitude',-180,180)}; }
function list(value,name){if(!Array.isArray(value)||value.length<1||value.length>30)fail(400,`Choose at least one ${name}.`);return [...new Set(value.map(x=>text(x,name,1,100)))];}
const crops = ['Grape','Pomegranate','Onion','Vegetables','Guava','General farm work','Animal husbandry'];
const dateValue = value => {if(typeof value!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(value)||Number.isNaN(Date.parse(value+'T00:00:00Z'))||new Date(value+'T00:00:00Z').toISOString().slice(0,10)!==value||value<today())fail(400,'Choose today or a future work date.');return value;};
async function readBody(req){let size=0,parts=[];for await(const part of req){size+=part.length;if(size>16384)fail(413,'Request is too large.');parts.push(part);}try{const body=JSON.parse(Buffer.concat(parts).toString()||'{}');if(!body||typeof body!=='object'||Array.isArray(body))fail(400,'Use a JSON object.');return body;}catch(e){if(e.status)throw e;fail(400,'Invalid JSON.');}}
export function createApp({dbPath=':memory:',origins=['http://localhost:5173'],serveStatic=false,trustProxy=false,otpService=createOtpService(),legacyPasswordAuth=false}={}){
 if(dbPath!==':memory:'){mkdirSync(dirname(resolve(dbPath)),{recursive:true,mode:0o700});}
 const db = new DatabaseSync(dbPath);if(dbPath!==':memory:')chmodSync(dbPath,0o600);
 db.exec(`PRAGMA foreign_keys=ON; PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000;
 CREATE TABLE IF NOT EXISTS users(id INTEGER PRIMARY KEY,name TEXT NOT NULL,phone TEXT UNIQUE NOT NULL,age INTEGER NOT NULL,password TEXT NOT NULL,salt TEXT NOT NULL,role TEXT NOT NULL CHECK(role IN ('farmer','provider')),address TEXT NOT NULL,lat REAL,lng REAL);
 CREATE TABLE IF NOT EXISTS sessions(token_hash TEXT PRIMARY KEY,user_id INTEGER NOT NULL REFERENCES users(id),expires INTEGER NOT NULL);
 CREATE TABLE IF NOT EXISTS teams(id INTEGER PRIMARY KEY,provider_id INTEGER UNIQUE NOT NULL REFERENCES users(id),name TEXT NOT NULL,place TEXT NOT NULL,crops TEXT NOT NULL,skills TEXT NOT NULL,people INTEGER NOT NULL,price INTEGER NOT NULL,lat REAL NOT NULL,lng REAL NOT NULL,available INTEGER NOT NULL DEFAULT 1);
 CREATE TABLE IF NOT EXISTS bookings(id INTEGER PRIMARY KEY,farmer_id INTEGER NOT NULL REFERENCES users(id),team_id INTEGER NOT NULL REFERENCES teams(id),team_name TEXT NOT NULL,task TEXT NOT NULL,date TEXT NOT NULL,workers INTEGER NOT NULL,address TEXT NOT NULL,lat REAL,lng REAL,price INTEGER NOT NULL,total INTEGER NOT NULL,status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','accepted','declined','cancelled','completed')),request_key TEXT NOT NULL,created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,UNIQUE(farmer_id,request_key));
 CREATE INDEX IF NOT EXISTS bookings_team_date ON bookings(team_id,date,status);
 CREATE INDEX IF NOT EXISTS bookings_farmer ON bookings(farmer_id);
 CREATE INDEX IF NOT EXISTS sessions_expiry ON sessions(expires);`);
 // Additive migration for databases created by the initial booking implementation.
 if(!db.prepare('PRAGMA table_info(users)').all().some(c=>c.name==='location_updated_at'))db.exec('ALTER TABLE users ADD COLUMN location_updated_at TEXT');
 if(!db.prepare('PRAGMA table_info(bookings)').all().some(c=>c.name==='location_sharing'))db.exec('ALTER TABLE bookings ADD COLUMN location_sharing INTEGER NOT NULL DEFAULT 0');
 if(!db.prepare('PRAGMA table_info(users)').all().some(c=>c.name==='suspended'))db.exec('ALTER TABLE users ADD COLUMN suspended INTEGER NOT NULL DEFAULT 0');
 if(!db.prepare('PRAGMA table_info(users)').all().some(c=>c.name==='created_at'))db.exec("ALTER TABLE users ADD COLUMN created_at TEXT NOT NULL DEFAULT ''");
 if(!db.prepare('PRAGMA table_info(teams)').all().some(c=>c.name==='verified'))db.exec('ALTER TABLE teams ADD COLUMN verified INTEGER NOT NULL DEFAULT 0');
 if(!db.prepare('PRAGMA table_info(teams)').all().some(c=>c.name==='admin_hidden'))db.exec('ALTER TABLE teams ADD COLUMN admin_hidden INTEGER NOT NULL DEFAULT 0');
 db.exec(`CREATE TABLE IF NOT EXISTS admins(id INTEGER PRIMARY KEY,name TEXT NOT NULL,phone TEXT UNIQUE NOT NULL,password TEXT NOT NULL,salt TEXT NOT NULL,active INTEGER NOT NULL DEFAULT 1,must_change INTEGER NOT NULL DEFAULT 1);
 CREATE TABLE IF NOT EXISTS admin_sessions(token_hash TEXT PRIMARY KEY,admin_id INTEGER NOT NULL REFERENCES admins(id),expires INTEGER NOT NULL);
 CREATE TABLE IF NOT EXISTS admin_audit(id INTEGER PRIMARY KEY,admin_id INTEGER NOT NULL REFERENCES admins(id),action TEXT NOT NULL,target_type TEXT NOT NULL,target_id INTEGER NOT NULL,detail TEXT,created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP);`);
 db.exec(`CREATE TABLE IF NOT EXISTS otp_challenges(phone TEXT PRIMARY KEY,expires INTEGER NOT NULL,attempts INTEGER NOT NULL DEFAULT 0,sent_at INTEGER NOT NULL,window_start INTEGER NOT NULL,window_count INTEGER NOT NULL DEFAULT 1);
 CREATE TABLE IF NOT EXISTS otp_signup_tickets(token_hash TEXT PRIMARY KEY,phone TEXT NOT NULL,expires INTEGER NOT NULL);`);
 const attempts=new Map();
 const userFor=req=>{const token=req.headers.authorization?.match(/^Bearer ([a-f0-9]{64})$/)?.[1];if(!token)fail(401,'Please sign in.');const tokenHash=hash(token);const admin=db.prepare('SELECT a.* FROM admins a JOIN admin_sessions s ON s.admin_id=a.id WHERE s.token_hash=? AND s.expires>? AND a.active=1').get(tokenHash,Date.now());if(admin)return {...admin,role:'admin',address:'KVK Solapur-I',age:null,lat:null,lng:null};const u=db.prepare('SELECT u.* FROM users u JOIN sessions s ON s.user_id=u.id WHERE s.token_hash=? AND s.expires>? AND u.suspended=0').get(tokenHash,Date.now());if(!u)fail(401,'Your session expired or this account was disabled. Please sign in again.');return u;};
 const role=(u,r)=>{if(u.role!==r)fail(403,`This action requires a ${r} account.`);};
 const adminFor=req=>{const u=userFor(req);role(u,'admin');if(u.must_change)fail(403,'Change your temporary admin password first.');return u;};
 const audit=(u,action,targetType,targetId,detail='')=>db.prepare('INSERT INTO admin_audit(admin_id,action,target_type,target_id,detail) VALUES(?,?,?,?,?)').run(u.id,action,targetType,targetId,detail);
 const session=u=>{const token=randomBytes(32).toString('hex');const admin=u.role==='admin';db.prepare(`DELETE FROM ${admin?'admin_sessions':'sessions'} WHERE expires<=?`).run(Date.now());db.prepare(`INSERT INTO ${admin?'admin_sessions':'sessions'} VALUES(?,?,?)`).run(hash(token),u.id,Date.now()+(admin?8*3600000:7*86400000));return {token,user:{...publicUser(u),mustChangePassword:admin?!!u.must_change:undefined}};};
 const teamPublic=(t,lat,lng)=>({id:t.id,name:t.name,place:t.place,crops:JSON.parse(t.crops),skills:JSON.parse(t.skills),people:t.people,price:t.price,available:!!t.available,verified:!!t.verified,distanceKm:lat==null?null:Math.round(distanceKm(lat,lng,t.lat,t.lng)*10)/10});
 const bookingPublic=b=>({id:b.id,teamId:b.team_id,team:b.team_name,task:b.task,date:b.date,workers:b.workers,address:b.address,lat:b.lat,lng:b.lng,price:b.price,total:b.total,status:b.status,createdAt:b.created_at,farmerName:b.farmer_name,farmerPhone:b.farmer_phone,providerName:b.provider_name,providerPhone:b.provider_phone,locationSharing:!!b.location_sharing&&b.status==='accepted',providerLocation:b.location_sharing&&b.status==='accepted'&&b.provider_lat!=null&&b.provider_updated_at&&Date.now()-Date.parse(b.provider_updated_at)<=300000?{lat:b.provider_lat,lng:b.provider_lng,updatedAt:b.provider_updated_at}:null});
 const bookingsFor=u=>db.prepare(`SELECT b.*,f.name farmer_name,f.phone farmer_phone,p.name provider_name,p.phone provider_phone,p.lat provider_lat,p.lng provider_lng,p.location_updated_at provider_updated_at FROM bookings b JOIN users f ON f.id=b.farmer_id JOIN teams t ON t.id=b.team_id JOIN users p ON p.id=t.provider_id WHERE ${u.role==='farmer'?'b.farmer_id':'t.provider_id'}=? ORDER BY b.id DESC`).all(u.id).map(bookingPublic);
 const transaction=fn=>{db.exec('BEGIN IMMEDIATE');try{const result=fn();db.exec('COMMIT');return result;}catch(e){db.exec('ROLLBACK');throw e;}};
 const server=createServer(async(req,res)=>{
  res.setHeader('X-Content-Type-Options','nosniff');res.setHeader('Referrer-Policy','same-origin');
  const origin=req.headers.origin;if(origin&&!origins.includes(origin)){res.writeHead(403,{'Content-Type':'application/json'});res.end(JSON.stringify({error:'Origin not allowed.'}));return;}
  if(origin){res.setHeader('Access-Control-Allow-Origin',origin);res.setHeader('Vary','Origin');res.setHeader('Access-Control-Allow-Headers','Content-Type, Authorization');res.setHeader('Access-Control-Allow-Methods','GET,POST,PUT,PATCH,OPTIONS');}
  if(req.method==='OPTIONS'){res.writeHead(204);res.end();return;}
  const send=(status,data)=>{res.writeHead(status,{'Content-Type':'application/json','Cache-Control':'no-store'});res.end(JSON.stringify(data));};
  try{
   const url=new URL(req.url,'http://localhost');const path=url.pathname;const method=req.method;
   if(path==='/api/health'&&method==='GET')return send(200,{status:'ok'});
   if(path==='/api/auth/otp/request'&&method==='POST'){
    const ip=trustProxy&&typeof req.headers['x-forwarded-for']==='string'?req.headers['x-forwarded-for'].split(',').at(-1).trim():req.socket.remoteAddress;
    const key=`otp:${ip}`,now=Date.now(),limit=attempts.get(key);
    if(limit&&limit.until>now&&limit.count>=30)fail(429,'Too many SMS requests. Try again later.');
    attempts.set(key,{count:limit&&limit.until>now?limit.count+1:1,until:limit&&limit.until>now?limit.until:now+900000});
    const b=await readBody(req),phone=text(b.phone,'Mobile number',10,10);
    if(!/^[6-9]\d{9}$/.test(phone))fail(400,'Enter a valid 10-digit Indian mobile number.');
    const old=db.prepare('SELECT * FROM otp_challenges WHERE phone=?').get(phone);
    if(old&&now-old.sent_at<60000)fail(429,'Please wait one minute before requesting another code.');
    if(old&&now-old.window_start<3600000&&old.window_count>=5)fail(429,'Too many codes requested. Try again in one hour.');
    await otpService.send(phone);
    const windowStart=old&&now-old.window_start<3600000?old.window_start:now;
    const windowCount=old&&now-old.window_start<3600000?old.window_count+1:1;
    db.prepare('INSERT INTO otp_challenges(phone,expires,attempts,sent_at,window_start,window_count) VALUES(?,?,0,?,?,?) ON CONFLICT(phone) DO UPDATE SET expires=excluded.expires,attempts=0,sent_at=excluded.sent_at,window_start=excluded.window_start,window_count=excluded.window_count').run(phone,now+300000,now,windowStart,windowCount);
    return send(200,{sent:true,expiresIn:300});
   }
   if(path==='/api/auth/otp/verify'&&method==='POST'){
    const b=await readBody(req),phone=text(b.phone,'Mobile number',10,10),code=text(b.code,'Verification code',6,6);
    if(!/^[6-9]\d{9}$/.test(phone)||!/^[0-9]{6}$/.test(code))fail(400,'Enter the mobile number and six-digit code.');
    const challenge=db.prepare('SELECT * FROM otp_challenges WHERE phone=?').get(phone);
    if(!challenge||challenge.expires<Date.now()||challenge.attempts>=5)fail(401,'Code expired or too many attempts. Request a new code.');
    db.prepare('UPDATE otp_challenges SET attempts=attempts+1 WHERE phone=?').run(phone);
    if(!await otpService.verify(phone,code))fail(401,'Code is incorrect. Please try again.');
    db.prepare('DELETE FROM otp_challenges WHERE phone=?').run(phone);
    const u=db.prepare('SELECT * FROM users WHERE phone=?').get(phone);
    if(u){if(u.suspended)fail(403,'This account is disabled. Please contact KVK.');return send(200,session(u));}
    const ticket=randomBytes(32).toString('hex');db.prepare('DELETE FROM otp_signup_tickets WHERE phone=? OR expires<?').run(phone,Date.now());
    db.prepare('INSERT INTO otp_signup_tickets(token_hash,phone,expires) VALUES(?,?,?)').run(hash(ticket),phone,Date.now()+600000);
    return send(200,{needsProfile:true,signupToken:ticket});
   }
   if(path==='/api/auth/otp/complete'&&method==='POST'){
    const b=await readBody(req),ticket=text(b.signupToken,'Verification ticket',64,64);
    if(!/^[a-f0-9]{64}$/.test(ticket))fail(400,'Invalid verification ticket.');
    const row=db.prepare('SELECT * FROM otp_signup_tickets WHERE token_hash=? AND expires>?').get(hash(ticket),Date.now());
    if(!row)fail(401,'Verification expired. Please request a new code.');
    const name=text(b.name,'Name',2,100),age=integer(b.age,'Age',18,110),address=text(b.address,'Village / address',3,300),userRole=b.role||'farmer';
    if(!['farmer','provider'].includes(userRole))fail(400,'Choose farmer or labour provider.');
    const loc=coordinates(b),password=randomBytes(32).toString('hex'),salt=randomBytes(16).toString('hex'),pass=(await derive(password,salt,64)).toString('hex');
    let u;
    transaction(()=>{
     const consumed=db.prepare('DELETE FROM otp_signup_tickets WHERE token_hash=? AND expires>?').run(hash(ticket),Date.now());
     if(!consumed.changes)fail(401,'Verification expired. Please request a new code.');
     if(db.prepare('SELECT id FROM users WHERE phone=?').get(row.phone))fail(409,'This mobile number is already registered. Please sign in.');
     const result=db.prepare('INSERT INTO users(name,phone,age,password,salt,role,address,lat,lng) VALUES(?,?,?,?,?,?,?,?,?)').run(name,row.phone,age,pass,salt,userRole,address,loc.lat,loc.lng);
     u=db.prepare('SELECT * FROM users WHERE id=?').get(Number(result.lastInsertRowid));
    });
    return send(201,session(u));
   }
   if(['/api/auth/register','/api/auth/login','/api/admin/login'].includes(path)&&method==='POST'){
    if(path!=='/api/admin/login'&&!legacyPasswordAuth)fail(410,'Use SMS code to sign in. Update the app to continue.');
    const ip=trustProxy&&typeof req.headers['x-forwarded-for']==='string'?req.headers['x-forwarded-for'].split(',').at(-1).trim():req.socket.remoteAddress;const now=Date.now();for(const [key,value]of attempts)if(value.until<now)attempts.delete(key);
    let attempt=attempts.get(ip)||{count:0,until:now+900000};if(++attempt.count>30)fail(429,'Too many sign-in attempts. Try again in 15 minutes.');attempts.set(ip,attempt);
    const b=await readBody(req);const phone=text(b.phone,'Mobile number',10,10);if(!/^[6-9]\d{9}$/.test(phone))fail(400,'Enter a valid 10-digit Indian mobile number.');
    const password=text(b.password,'Password',8,128);let u;
    if(path.endsWith('register')){
     const name=text(b.name,'Name',2,100),age=integer(b.age,'Age',18,110),address=text(b.address,'Address',3,300);if(!['farmer','provider'].includes(b.role))fail(400,'Choose farmer or labour provider.');const loc=coordinates(b);
     if(db.prepare('SELECT id FROM users WHERE phone=?').get(phone)||db.prepare('SELECT id FROM admins WHERE phone=?').get(phone))fail(409,'This mobile number is already registered. Please sign in.');
     const salt=randomBytes(16).toString('hex');const pass=(await derive(password,salt,64)).toString('hex');
     try{const result=db.prepare('INSERT INTO users(name,phone,age,password,salt,role,address,lat,lng) VALUES(?,?,?,?,?,?,?,?,?)').run(name,phone,age,pass,salt,b.role,address,loc.lat,loc.lng);u=db.prepare('SELECT * FROM users WHERE id=?').get(Number(result.lastInsertRowid));}catch(e){if(e.message.includes('UNIQUE'))fail(409,'This mobile number is already registered.');throw e;}
    }else if(path==='/api/admin/login'){
     const admin=db.prepare('SELECT * FROM admins WHERE phone=? AND active=1').get(phone);const derived=await derive(password,admin?.salt||'00000000000000000000000000000000',64);
     if(!admin||!timingSafeEqual(derived,Buffer.from(admin.password,'hex')))fail(401,'Admin mobile number or password is incorrect.');
     u={...admin,role:'admin',address:'KVK Solapur-I',age:null,lat:null,lng:null};
    }else{
     u=db.prepare('SELECT * FROM users WHERE phone=?').get(phone);const derived=await derive(password,u?.salt||'00000000000000000000000000000000',64);if(!u||!timingSafeEqual(derived,Buffer.from(u.password,'hex')))fail(401,'Mobile number or password is incorrect.');
    }
    return send(path.endsWith('register')?201:200,session(u));
   }
   if(path==='/api/auth/logout'&&method==='POST'){const u=userFor(req);db.prepare(`DELETE FROM ${u.role==='admin'?'admin_sessions':'sessions'} WHERE token_hash=?`).run(hash(req.headers.authorization.slice(7)));return send(200,{ok:true});}
   if(path==='/api/me'&&method==='GET')return send(200,{user:publicUser(userFor(req))});
   if(path==='/api/me'&&method==='PATCH'){
    const u=userFor(req);if(u.role==='admin')fail(403,'Use admin account settings.');const b=await readBody(req);const loc=b.lat===undefined&&b.lng===undefined?{lat:u.lat,lng:u.lng}:coordinates(b);
    const name=b.name===undefined?u.name:text(b.name,'Name',2,100),address=b.address===undefined?u.address:text(b.address,'Address',3,300),age=b.age===undefined?u.age:integer(b.age,'Age',18,110);
    db.prepare('UPDATE users SET name=?,address=?,age=?,lat=?,lng=?,location_updated_at=? WHERE id=?').run(name,address,age,loc.lat,loc.lng,b.lat===undefined&&b.lng===undefined?u.location_updated_at:new Date().toISOString(),u.id);return send(200,{user:publicUser(db.prepare('SELECT * FROM users WHERE id=?').get(u.id))});
   }
   if(path==='/api/admin/password'&&method==='PATCH'){
    const u=userFor(req);role(u,'admin');const b=await readBody(req),old=text(b.currentPassword,'Current password',8,128),next=text(b.newPassword,'New password',12,128);
    const derived=await derive(old,u.salt,64);if(!timingSafeEqual(derived,Buffer.from(u.password,'hex')))fail(401,'Current password is incorrect.');if(old===next)fail(400,'Choose a different password.');
    const salt=randomBytes(16).toString('hex'),password=(await derive(next,salt,64)).toString('hex');
    db.prepare('UPDATE admins SET password=?,salt=?,must_change=0 WHERE id=?').run(password,salt,u.id);
    db.prepare('DELETE FROM admin_sessions WHERE admin_id=? AND token_hash<>?').run(u.id,hash(req.headers.authorization.slice(7)));
    audit(u,'password_changed','admin',u.id);return send(200,{user:publicUser({...u,must_change:0})});
   }
   if(path==='/api/teams'&&method==='GET'){
    const hasLoc=url.searchParams.has('lat')||url.searchParams.has('lng');let loc={lat:null,lng:null};if(hasLoc&&(!url.searchParams.has('lat')||!url.searchParams.has('lng')))fail(400,'Provide both latitude and longitude.');if(hasLoc&&(!url.searchParams.get('lat')?.trim()||!url.searchParams.get('lng')?.trim()))fail(400,'Coordinates cannot be empty.');if(hasLoc)loc=coordinates({lat:Number(url.searchParams.get('lat')),lng:Number(url.searchParams.get('lng'))},true);
    const radius=url.searchParams.has('radius')?number(Number(url.searchParams.get('radius')),'Search radius',1,500):50;const crop=url.searchParams.get('crop');const q=(url.searchParams.get('q')||'').slice(0,100).toLowerCase();
    const teams=db.prepare('SELECT t.* FROM teams t JOIN users u ON u.id=t.provider_id WHERE t.available=1 AND t.admin_hidden=0 AND u.suspended=0').all().map(t=>teamPublic(t,loc.lat,loc.lng)).filter(t=>(loc.lat==null||t.distanceKm<=radius)&&(!crop||crop==='All crops'||t.crops.includes(crop))&&`${t.name} ${t.skills.join(' ')}`.toLowerCase().includes(q)).sort((a,b)=>(a.distanceKm??0)-(b.distanceKm??0));
    return send(200,{teams});
   }
   if(path==='/api/admin/overview'&&method==='GET'){
    adminFor(req);
    const count=(table,where='1=1')=>db.prepare(`SELECT COUNT(*) n FROM ${table} WHERE ${where}`).get().n;
    return send(200,{counts:{farmers:count('users',"role='farmer'"),providers:count('users',"role='provider'"),activeUsers:count('users','suspended=0'),teams:count('teams'),unverifiedTeams:count('teams','verified=0'),pendingBookings:count('bookings',"status='pending'"),acceptedBookings:count('bookings',"status='accepted'")}});
   }
   if(path==='/api/admin/users'&&method==='GET'){
    adminFor(req);return send(200,{users:db.prepare('SELECT id,name,phone,age,role,address,suspended,created_at FROM users ORDER BY id DESC').all().map(u=>({...u,suspended:!!u.suspended}))});
   }
   const userToggle=path.match(/^\/api\/admin\/users\/(\d+)$/);
   if(userToggle&&method==='PATCH'){
    const admin=adminFor(req),id=Number(userToggle[1]),b=await readBody(req);if(typeof b.suspended!=='boolean')fail(400,'Choose whether to suspend this account.');
    const target=db.prepare('SELECT id,role,suspended FROM users WHERE id=?').get(id);if(!target)fail(404,'Account not found.');
    transaction(()=>{db.prepare('UPDATE users SET suspended=? WHERE id=?').run(b.suspended?1:0,id);if(b.suspended){db.prepare('DELETE FROM sessions WHERE user_id=?').run(id);if(target.role==='provider')db.prepare('UPDATE bookings SET location_sharing=0 WHERE team_id IN (SELECT id FROM teams WHERE provider_id=?)').run(id);}audit(admin,b.suspended?'user_suspended':'user_restored','user',id);});
    return send(200,{user:{...target,suspended:b.suspended}});
   }
   if(path==='/api/admin/teams'&&method==='GET'){
    adminFor(req);return send(200,{teams:db.prepare('SELECT t.*,u.name provider_name,u.phone provider_phone,u.suspended provider_suspended FROM teams t JOIN users u ON u.id=t.provider_id ORDER BY t.id DESC').all().map(t=>({...teamPublic(t,null,null),providerId:t.provider_id,providerName:t.provider_name,providerPhone:t.provider_phone,providerSuspended:!!t.provider_suspended,adminHidden:!!t.admin_hidden,lat:t.lat,lng:t.lng}))});
   }
   const teamToggle=path.match(/^\/api\/admin\/teams\/(\d+)$/);
   if(teamToggle&&method==='PATCH'){
    const admin=adminFor(req),id=Number(teamToggle[1]),b=await readBody(req);const hasVerified=typeof b.verified==='boolean',hasHidden=typeof b.adminHidden==='boolean';if(!hasVerified&&!hasHidden)fail(400,'Choose verification or listing visibility.');if((b.verified!==undefined&&!hasVerified)||(b.adminHidden!==undefined&&!hasHidden))fail(400,'Use true or false for team settings.');
    const t=db.prepare('SELECT * FROM teams WHERE id=?').get(id);if(!t)fail(404,'Team not found.');
    transaction(()=>{db.prepare('UPDATE teams SET verified=?,admin_hidden=? WHERE id=?').run(hasVerified?(b.verified?1:0):t.verified,hasHidden?(b.adminHidden?1:0):t.admin_hidden,id);audit(admin,'team_updated','team',id,JSON.stringify({verified:hasVerified?b.verified:!!t.verified,adminHidden:hasHidden?b.adminHidden:!!t.admin_hidden}));});
    return send(200,{team:teamPublic(db.prepare('SELECT * FROM teams WHERE id=?').get(id),null,null)});
   }
   if(path==='/api/admin/bookings'&&method==='GET'){
    adminFor(req);return send(200,{bookings:db.prepare('SELECT b.id,b.team_id teamId,b.team_name team,b.task,b.date,b.workers,b.address,b.price,b.total,b.status,b.created_at createdAt,f.name farmerName,f.phone farmerPhone,p.name providerName,p.phone providerPhone FROM bookings b JOIN users f ON f.id=b.farmer_id JOIN teams t ON t.id=b.team_id JOIN users p ON p.id=t.provider_id ORDER BY b.id DESC').all()});
   }
   const adminBooking=path.match(/^\/api\/admin\/bookings\/(\d+)\/cancel$/);
   if(adminBooking&&method==='POST'){
    const admin=adminFor(req),id=Number(adminBooking[1]),b=await readBody(req),reason=text(b.reason,'Cancellation reason',5,300);
    transaction(()=>{const booking=db.prepare('SELECT status FROM bookings WHERE id=?').get(id);if(!booking)fail(404,'Booking not found.');if(!['pending','accepted'].includes(booking.status))fail(409,'Only pending or accepted bookings can be cancelled.');db.prepare("UPDATE bookings SET status='cancelled',location_sharing=0 WHERE id=?").run(id);audit(admin,'booking_cancelled','booking',id,reason);});
    return send(200,{booking:{id,status:'cancelled'}});
   }
   if(path==='/api/admin/audit'&&method==='GET'){
    adminFor(req);return send(200,{events:db.prepare('SELECT a.id,a.action,a.target_type targetType,a.target_id targetId,a.detail,a.created_at createdAt,u.name adminName FROM admin_audit a JOIN admins u ON u.id=a.admin_id ORDER BY a.id DESC LIMIT 100').all()});
   }
   if(path==='/api/admin/admins'&&method==='GET'){
    adminFor(req);return send(200,{admins:db.prepare('SELECT id,name,phone,active,must_change mustChangePassword FROM admins ORDER BY id').all().map(a=>({...a,active:!!a.active,mustChangePassword:!!a.mustChangePassword}))});
   }
   if(path==='/api/admin/admins'&&method==='POST'){
    const admin=adminFor(req),b=await readBody(req),name=text(b.name,'Admin name',2,100),phone=text(b.phone,'Mobile number',10,10),password=text(b.password,'Temporary password',12,128);if(!/^[6-9]\d{9}$/.test(phone))fail(400,'Enter a valid 10-digit Indian mobile number.');if(db.prepare('SELECT id FROM admins WHERE phone=?').get(phone))fail(409,'This mobile number already has an admin account.');
    const salt=randomBytes(16).toString('hex'),pass=(await derive(password,salt,64)).toString('hex');const id=transaction(()=>{const result=db.prepare('INSERT INTO admins(name,phone,password,salt) VALUES(?,?,?,?)').run(name,phone,pass,salt);audit(admin,'admin_created','admin',Number(result.lastInsertRowid));return Number(result.lastInsertRowid);});return send(201,{admin:{id,name,phone,mustChangePassword:true}});
   }
   if(path==='/api/provider/team'&&method==='GET'){const u=userFor(req);role(u,'provider');const t=db.prepare('SELECT * FROM teams WHERE provider_id=?').get(u.id);return send(200,{team:t?{...teamPublic(t,null,null),lat:t.lat,lng:t.lng}:null});}
   if(path==='/api/provider/team'&&method==='PUT'){
    const u=userFor(req);role(u,'provider');const b=await readBody(req);const name=text(b.name,'Team name',2,100),place=text(b.place,'Village / area',2,150),skills=list(b.skills,'skill'),cs=list(b.crops,'crop');if(cs.some(c=>!crops.includes(c)))fail(400,'Choose crops from the supported list.');
    const people=integer(b.people,'Team size',1,500),price=integer(b.price,'Daily price',1,100000),loc=coordinates(b,true);if(typeof b.available!=='boolean')fail(400,'Choose available or unavailable.');
    const t=transaction(()=>{
     const current=db.prepare('SELECT id FROM teams WHERE provider_id=?').get(u.id);if(current){const peak=db.prepare("SELECT SUM(workers) n FROM bookings WHERE team_id=? AND status IN ('accepted','completed') AND date>=? GROUP BY date ORDER BY n DESC LIMIT 1").get(current.id,today());if((peak?.n||0)>people)fail(409,'Team size cannot be lower than your confirmed bookings.');}
     db.prepare('INSERT INTO teams(provider_id,name,place,crops,skills,people,price,lat,lng,available) VALUES(?,?,?,?,?,?,?,?,?,?) ON CONFLICT(provider_id) DO UPDATE SET name=excluded.name,place=excluded.place,crops=excluded.crops,skills=excluded.skills,people=excluded.people,price=excluded.price,lat=excluded.lat,lng=excluded.lng,available=excluded.available').run(u.id,name,place,JSON.stringify(cs),JSON.stringify(skills),people,price,loc.lat,loc.lng,b.available?1:0);
     return db.prepare('SELECT * FROM teams WHERE provider_id=?').get(u.id);
    });return send(200,{team:{...teamPublic(t,null,null),lat:t.lat,lng:t.lng}});
   }
   if(path==='/api/bookings'&&method==='GET')return send(200,{bookings:bookingsFor(userFor(req))});
   if(path==='/api/bookings'&&method==='POST'){
    const u=userFor(req);role(u,'farmer');const b=await readBody(req);const key=text(b.requestKey,'Request key',16,100);if(!/^[a-zA-Z0-9-]+$/.test(key))fail(400,'Invalid request key.');
    const result=transaction(()=>{
     const existing=db.prepare('SELECT id FROM bookings WHERE farmer_id=? AND request_key=?').get(u.id,key);if(existing)return {id:existing.id,replayed:true};
     const team=db.prepare('SELECT t.* FROM teams t JOIN users p ON p.id=t.provider_id WHERE t.id=? AND p.suspended=0 AND t.admin_hidden=0').get(integer(b.teamId,'Team',1,Number.MAX_SAFE_INTEGER));if(!team||!team.available)fail(409,'This team is unavailable. Choose another team.');
     const task=text(b.task,'Farm task',1,100);if(!JSON.parse(team.skills).includes(task))fail(400,'Choose a skill offered by this team.');const date=dateValue(b.date),workers=integer(b.workers,'Workers',1,team.people),address=text(b.address,'Farm address',3,300),loc=coordinates(b);
     const reserved=db.prepare("SELECT COALESCE(SUM(workers),0) n FROM bookings WHERE team_id=? AND date=? AND status IN ('accepted','completed')").get(team.id,date).n;if(reserved+workers>team.people)fail(409,'Not enough workers are available on this date.');
     const inserted=db.prepare('INSERT INTO bookings(farmer_id,team_id,team_name,task,date,workers,address,lat,lng,price,total,request_key) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)').run(u.id,team.id,team.name,task,date,workers,address,loc.lat,loc.lng,team.price,workers*team.price,key);return {id:Number(inserted.lastInsertRowid),replayed:false};
    });return send(result.replayed?200:201,{booking:bookingsFor(u).find(x=>x.id===result.id)});
   }
   const sharing=path.match(/^\/api\/bookings\/(\d+)\/location-sharing$/);
   if(sharing&&method==='PATCH'){
    const u=userFor(req);role(u,'provider');const b=await readBody(req),id=Number(sharing[1]);if(typeof b.enabled!=='boolean')fail(400,'Choose whether to share your location.');
    const booking=db.prepare('SELECT b.status,t.provider_id FROM bookings b JOIN teams t ON t.id=b.team_id WHERE b.id=?').get(id);if(!booking||booking.provider_id!==u.id)fail(404,'Booking not found.');if(b.enabled&&(u.lat==null||u.lng==null||!u.location_updated_at||Date.now()-Date.parse(u.location_updated_at)>300000))fail(409,'Update your GPS location before sharing it.');if(booking.status!=='accepted')fail(409,'GPS sharing is available only for confirmed bookings.');
    db.prepare('UPDATE bookings SET location_sharing=? WHERE id=?').run(b.enabled?1:0,id);return send(200,{booking:bookingsFor(u).find(x=>x.id===id)});
   }
   const match=path.match(/^\/api\/bookings\/(\d+)\/status$/);
   if(match&&method==='PATCH'){
    const u=userFor(req),b=await readBody(req),id=Number(match[1]);transaction(()=>{
     const booking=db.prepare('SELECT b.*,t.provider_id,t.people FROM bookings b JOIN teams t ON t.id=b.team_id WHERE b.id=?').get(id);if(!booking||(u.role==='farmer'?booking.farmer_id:booking.provider_id)!==u.id)fail(404,'Booking not found.');
     const status=b.status;if(u.role==='farmer') {if(status!=='cancelled'||!['pending','accepted'].includes(booking.status))fail(409,'Only pending or accepted bookings can be cancelled.');}
     else{const permitted=(booking.status==='pending'&&['accepted','declined'].includes(status))||(booking.status==='accepted'&&status==='completed');if(!permitted)fail(409,'This booking cannot be changed to that status.');if(status==='accepted'){if(booking.date<today())fail(409,'This work date has passed. Please decline the request.');const reserved=db.prepare("SELECT COALESCE(SUM(workers),0) n FROM bookings WHERE team_id=? AND date=? AND status IN ('accepted','completed')").get(booking.team_id,booking.date).n;if(reserved+booking.workers>booking.people)fail(409,'Accepting this request would overbook your team.');}if(status==='completed'&&booking.date>today())fail(409,'Mark work completed after the work date begins.');}
     db.prepare("UPDATE bookings SET status=?,location_sharing=CASE WHEN ?='accepted' THEN location_sharing ELSE 0 END WHERE id=?").run(status,status,id);
    });return send(200,{booking:bookingsFor(u).find(x=>x.id===id)});
   }
   if(path.startsWith('/api/'))fail(404,'Endpoint not found.');
   if(serveStatic&&method==='GET'){
    const root=resolve('dist');const decoded=decodeURIComponent(path);let file=resolve(root,'.'+decoded);if(!file.startsWith(root+'/')&&file!==root)fail(404,'Not found.');if(path==='/admin'||path==='/admin/')file=resolve(root,'admin.html');else if(path==='/'||!extname(file))file=resolve(root,'index.html');
    try{const data=await readFile(file);const types={'.html':'text/html; charset=utf-8','.js':'text/javascript','.css':'text/css','.svg':'image/svg+xml','.png':'image/png','.ico':'image/x-icon'};res.writeHead(200,{'Content-Type':types[extname(file)]||'application/octet-stream','Cache-Control':extname(file)==='.html'?'no-cache':'public, max-age=3600'});res.end(data);return;}catch{fail(404,'Not found.');}
   }
   fail(404,'Not found.');
  }catch(e){if(!e.status)console.error('API error:',e.message);if(!res.headersSent)send(e.status||500,{error:e.status?e.message:'Something went wrong. Please try again.'});else res.end();}
 });
 server.requestTimeout=30000;server.headersTimeout=15000;
 return {server,db,close:()=>new Promise(resolve=>server.close(()=>{db.close();resolve();}))};
}
