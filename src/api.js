export class ApiError extends Error {constructor(message,status){super(message);this.status=status;}}
export async function api(path,{method='GET',body}={}){
 const token=sessionStorage.getItem('krishi-token');
 let response;
 try{response=await fetch('/api'+path,{method,headers:{...(token?{Authorization:`Bearer ${token}`} :{}),...(body?{'Content-Type':'application/json'}:{})},...(body?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(15000)});}catch{throw new ApiError('Cannot reach the service. Check your connection and try again.',0);}
 const data=await response.json().catch(()=>({error:'The server returned an invalid response.'}));
 if(!response.ok){if(response.status===401)sessionStorage.removeItem('krishi-token');throw new ApiError(data.error||'Please try again.',response.status);}
 return data;
}
export const esc=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export function gps(){return new Promise((resolve,reject)=>{if(!navigator.geolocation)return reject(new Error('GPS is not supported on this device.'));navigator.geolocation.getCurrentPosition(p=>resolve({lat:p.coords.latitude,lng:p.coords.longitude,accuracy:p.coords.accuracy}),e=>reject(new Error(({1:'Location permission was denied. You can enable it in browser settings.',2:'Location is unavailable. Turn on location services and try again.',3:'GPS timed out. Move to an open area and try again.'})[e.code]||'Could not get your location.')),{enableHighAccuracy:true,timeout:20000,maximumAge:0});});}
