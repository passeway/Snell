let body = $request.body;

try {
  let obj = JSON.parse(body);

  if (obj.phoneType) {
    obj.phoneType = obj.phoneType.replace("0211", "0000");
  }

  body = JSON.stringify(obj);

} catch (e) {
  body = body.replace(/0211/g, "0000");
}

$done({ body });
