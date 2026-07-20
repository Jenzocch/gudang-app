const CACHE_NAME='gudang-v3';

self.addEventListener('install',e=>{
  // 不再自動 skipWaiting：新版先進入 waiting 狀態，等使用者在畫面上按「Perbarui」接受更新
  // 才接管。這樣正在填表／領料／盤點的人不會被突然重載打斷。
});

self.addEventListener('message',e=>{
  // 只有使用者接受更新時，前端才會送這個訊息 → 這時才讓新版接管。
  if(e.data&&e.data.type==='SKIP_WAITING')self.skipWaiting();
});

self.addEventListener('activate',e=>{
  e.waitUntil(
    caches.keys()
      .then(keys=>Promise.all(keys.filter(k=>k!==CACHE_NAME).map(k=>caches.delete(k))))
      .then(()=>self.clients.claim())
    // 不再對所有分頁強制 navigate(c.url)。接管與重載完全交給前端：前端監聽 controllerchange，
    // 且只有在「使用者按過更新」後才 reload 一次；首次安裝或自發更新都不會重載。
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
