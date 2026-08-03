(function(){
  var info={ url: location.href, title: document.title };
  var body = (document.body.innerText||'').replace(/\s+/g,' ').trim();
  info.bodyHead = body.substring(0,600);
  // 找和 license / registration / BSC 有關的可見文字
  var kw = body.match(/[^.]*?(licens|registration key|Business Services|BSC|register|entitlement|online|internet)[^.]*\./gi);
  info.licenseText = kw ? kw.slice(0,8) : [];
  return JSON.stringify(info);
})()
