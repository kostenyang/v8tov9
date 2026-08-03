(function(){
  var out=[];
  ['button','input[type=submit]','a[role=button]','clr-button','[type=submit]'].forEach(function(sel){
    [].slice.call(document.querySelectorAll(sel)).forEach(function(e){
      out.push(sel+' | tag='+e.tagName+' type='+(e.type||'')+' disabled='+e.disabled+' txt="'+(e.textContent||e.value||'').trim().substring(0,30)+'"');
    });
  });
  return out.join(' || ');
})()
