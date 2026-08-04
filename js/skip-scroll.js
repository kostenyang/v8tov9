(function(){
  var all=[].slice.call(document.querySelectorAll('button, a, span'));
  var skip=all.find(function(x){return (x.textContent||'').trim().toLowerCase()==='skip';});
  if(skip){ skip.click(); }
  // 捲動：找含 UPGRADE SUMMARY 的可捲容器往下捲
  window.scrollTo(0, 500);
  var cards=[].slice.call(document.querySelectorAll('div'));
  cards.forEach(function(d){ if(d.scrollHeight>d.clientHeight+50 && /Upgrade Hosts|UPGRADE SUMMARY/.test(d.textContent||'')){ d.scrollTop = d.scrollHeight; } });
  return 'scrolled';
})()
