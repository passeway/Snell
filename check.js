let obj = JSON.parse($response.body);

if (obj && obj.response && obj.response.head) {
  obj.response.head.respCode = "0000";
  obj.response.head.respMsg = "成功";
}

$done({ body: JSON.stringify(obj) });
