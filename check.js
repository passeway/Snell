let body = $request.body;

function log(title, data) {
  console.log(`[10010-LOG] ${title}: ${data}`);
}

log("原始body", body || "null");

if (!body) {
  log("结果", "body为空，直接放行");
  $done({});
}

try {
  let obj = JSON.parse(body);
  log("解析JSON成功", JSON.stringify(obj));

// 修改字段（兼容多字段）
  let changed = false;

  ["phoneType", "type", "code"].forEach(k => {
    if (obj[k] && typeof obj[k] === "string" && obj[k].includes("0211")) {
      log("命中字段", `${k} = ${obj[k]}`);
      obj[k] = obj[k].replace("0211", "0000");
      changed = true;
    }
  });

  if (changed) {
    body = JSON.stringify(obj);
    log("修改后body", body);
  } else {
    log("状态", "未匹配任何字段");
  }

} catch (e) {
  log("JSON解析失败", e.toString());

  if (body.includes("0211")) {
    body = body.replace(/0211/g, "0000");
    log("字符串替换后body", body);
  } else {
    log("状态", "未发现0211");
  }
}

$done({ body });
