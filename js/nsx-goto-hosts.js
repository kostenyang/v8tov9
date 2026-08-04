(function(){
  // 先關導覽/彈窗
  var all=[].slice.call(document.querySelectorAll('button, a, span, div[role=button]'));
  var skip=all.find(function(x){var t=(x.textContent||'').trim().toLowerCase(); return t==='skip';});
  if(skip){ skip.click(); }
  // 點 "Upgrade Hosts" 進明細
  var h=all.find(function(x){return (x.textContent||'').trim()==='Upgrade Hosts';});
  if(h){ h.click(); return 'clicked Upgrade Hosts'; }
  return 'no Upgrade Hosts link';
})()
