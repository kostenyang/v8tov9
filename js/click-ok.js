(function(){
  var btns=[].slice.call(document.querySelectorAll('button, a[role=button], .btn'));
  var b=btns.find(function(x){var t=(x.textContent||'').trim().toLowerCase(); return t==='ok'||t==='got it'||t==='accept'||t==='close'||t==='dismiss'||t==='skip'||t==='cancel';});
  if(b){ b.click(); return 'dismissed:'+b.textContent.trim(); }
  return 'no-modal-btn';
})()
