import {DatabaseSync} from 'node:sqlite';
import {randomBytes,scrypt} from 'node:crypto';
import {promisify} from 'node:util';
import {mkdirSync,writeFileSync,chmodSync,existsSync} from 'node:fs';
import {dirname,resolve} from 'node:path';
const phone=process.argv[2],name=process.argv[3]||'KVK Solapur-I Admin';
if(!/^[6-9]\d{9}$/.test(phone||'')){console.error('Usage: npm run admin:create -- 10_DIGIT_MOBILE "Admin name"');process.exit(1);}
const dbPath=resolve(process.env.DATABASE_PATH||'.data/krishi.sqlite');
mkdirSync(dirname(dbPath),{recursive:true,mode:0o700});
const db=new DatabaseSync(dbPath);
try{
 if(!db.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name='admins'").get()){console.error('Start the API once to initialize the database, then run this command.');process.exitCode=1;}
 else if(db.prepare('SELECT id FROM admins WHERE phone=?').get(phone)){console.error('That mobile number already has an account.');process.exitCode=1;}
 else if(existsSync(resolve(dirname(dbPath),'kvk-first-login.txt'))){console.error('The first-login credentials file already exists. Move it securely before creating another admin.');process.exitCode=1;}
 else{
  const password=randomBytes(18).toString('base64url');
  const salt=randomBytes(16).toString('hex');
  const hash=(await promisify(scrypt)(password,salt,64)).toString('hex');
  db.prepare('INSERT INTO admins(name,phone,password,salt) VALUES(?,?,?,?)').run(name,phone,hash,salt);
  const credentialsPath=resolve(dirname(dbPath),'kvk-first-login.txt');
  writeFileSync(credentialsPath,`KVK admin first login\nMobile: ${phone}\nTemporary password: ${password}\nOpen /admin in the web app. Change this password immediately after signing in.\n`,{mode:0o600,flag:'wx'});
  chmodSync(credentialsPath,0o600);
  console.log(`Created KVK admin ${name}. One-time credentials saved privately to ${credentialsPath}`);
 }
}finally{db.close();}
