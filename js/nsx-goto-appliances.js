(function(){
  // 直接設 Angular route 到 System > Appliances（顯示 NSX 版本）
  try { window.location.hash = '#/app/system/configuration/appliances/overview'; } catch(e){}
  // 同時嘗試點 "System" 頂層導覽（保險）
  var links=[].slice.call(document.querySelectorAll('a,button,[role=tab],[role=menuitem],span'));
  var sys=links.find(function(x){return (x.textContent||'').trim()==='System';});
  if(sys){ sys.click(); }
  return 'hash='+window.location.hash+' sysClicked='+(sys?'y':'n');
})()
