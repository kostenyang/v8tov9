(function(){
  // 勾選任何 EULA / accept 類的 checkbox 或 radio
  [].slice.call(document.querySelectorAll('input[type=checkbox], input[type=radio]')).forEach(function(c){
    var lbl=(c.closest('label')?c.closest('label').innerText:'')+' '+(c.getAttribute('aria-label')||'')+' '+(c.name||'')+' '+(c.id||'');
    if(/accept|agree|eula|terms|yes/i.test(lbl) && !c.checked){
      c.click();
    }
  });
  // 找主要前進鈕：NEXT / FINISH / ACCEPT / OK（避開 CANCEL/BACK）
  var els=[].slice.call(document.querySelectorAll('button, a[role=button], [type=submit], a.btn'));
  var order=['finish','next','accept','ok','complete','done'];
  var pick=null, pickRank=99;
  els.forEach(function(e){
    var t=(e.textContent||e.value||'').trim().toLowerCase();
    if(!t) return;
    if(/cancel|back|previous/.test(t)) return;
    for(var i=0;i<order.length;i++){ if(t===order[i] || t.indexOf(order[i])>-1){ if(i<pickRank){ pick=e; pickRank=i; } } }
  });
  if(pick){ pick.click(); return 'clicked:'+(pick.textContent||pick.value||'').trim(); }
  return 'no-advance-btn(els='+els.length+')';
})()
