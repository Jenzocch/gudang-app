const CACHE_NAME='gudang-v3';

self.addEventListener('install',e=>{
  self.skipWaiting();
});

self.addEventListener('activate',e=>{
  e.waitUntil(
    caches.keys()
      .then(keys=>Promise.all(keys.filter(k=>k!==CACHE_NAME).map(k=>caches.delete(k))))
      .then(()=>self.clients.claim())
      .then(()=>self.clients.matchAll({type:'window'}))
      .then(clients=>{clients.forEach(c=>c.navigate(c.url));})
  );
});

self.addEventListener('fetch',e=>{
  if(e.request.method!=='GET')return;
  const url=e.request.url;
  if(url.includes('supabase')||url.includes('telegram'))return;
  // 全部 network-first：永遠拿最新版
  e.respondWith(
    fetch(e.request).then(res=>{
      if(res&&res.status===200&&res.type==='basic'){
        const clone=res.clone();
        caches.open(CACHE_NAME).then(cache=>cache.put(e.request,clone));
      }
      return res;
    }).catch(()=>caches.match(e.request))
  );
});
