(function(){
  var els=[].slice.call(document.querySelectorAll('button, a[role=button], [type=submit], a.btn, clr-button'));
  var b=els.find(function(x){return /^\s*(log ?in|sign ?in)\s*$/i.test((x.textContent||x.value||'').trim());});
  if(!b){ b=els.find(function(x){return /log ?in|sign ?in/i.test((x.textContent||x.value||''));}); }
  if(b){ b.click(); return 'clicked:'+(b.tagName)+':'+(b.textContent||b.value||'').trim(); }
  return 'no-login-btn(els='+els.length+')';
})()
