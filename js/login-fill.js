(function(){
  function setVal(el,val){
    var d=Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype,'value').set;
    d.call(el,val);
    el.dispatchEvent(new Event('input',{bubbles:true}));
    el.dispatchEvent(new Event('change',{bubbles:true}));
  }
  var inputs=[].slice.call(document.querySelectorAll('input'));
  var u=inputs.find(function(i){return /user/i.test((i.name||'')+(i.id||'')+(i.getAttribute('formcontrolname')||'')+(i.getAttribute('placeholder')||''));});
  var p=inputs.find(function(i){return i.type==='password';});
  if(!u){ u=inputs.filter(function(i){return i.type==='text'||i.type==='';})[0]; }
  if(u) setVal(u,'admin');
  if(p) setVal(p,'<NSX_SDDC_OPS_PASSWORD>');
  return 'u='+(u?'yes':'no')+' p='+(p?'yes':'no')+' inputs='+inputs.length;
})()
