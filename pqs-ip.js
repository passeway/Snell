// === PQS 自动换 IP（远程版，变量由 Surge 参数传入） ===

// 从 Surge 模块参数获取变量
const CHECK_URL = $argument.CHECK_URL;
const CHANGE_URL = $argument.CHANGE_URL;
const REQUIRED_PREFIX = $argument.REQUIRED_PREFIX;
const TIMEOUT = 55000; // 55 秒

function log(type, msg) {
    const ts = new Date().toISOString().replace("T", " ").split(".")[0];
    console.log(`[${ts}] [${type}] ${msg}`);
}

function valid_ip(ip) {
    return /^(\d{1,3}\.){3}\d{1,3}$/.test(ip);
}

function get_ip(url) {
    return new Promise((resolve) => {
        $httpClient.get({ url: url, timeout: TIMEOUT }, function (err, resp, data) {
            if (err || !data) {
                log("ERROR", "API 调用失败");
                resolve("");
            } else {
                resolve(data.trim());
            }
        });
    });
}

async function run() {
    if (!CHECK_URL || !CHANGE_URL || !REQUIRED_PREFIX) {
        console.log("参数未填写，请前往 Surge 模块填写 CHECK_URL / CHANGE_URL / REQUIRED_PREFIX");
        $done();
        return;
    }

    let current_ip = await get_ip(CHECK_URL);

    if (!valid_ip(current_ip)) {
        log("ERROR", `查询失败或返回无效: ${current_ip || "nil"}`);
        $done();
        return;
    }

    log("CHECK", `当前 IP: ${current_ip}`);

    if (current_ip.startsWith(REQUIRED_PREFIX)) {
        log("VALID", `IP 符合要求 (${REQUIRED_PREFIX} 开头)`);
        $done();
        return;
    }

    log("INVALID", "IP 不符合要求，执行更换");

    let new_ip = await get_ip(CHANGE_URL);

    if (new_ip && valid_ip(new_ip)) {
        log("CHANGE", `更换完成: ${new_ip}`);

        if (new_ip.startsWith(REQUIRED_PREFIX)) {
            log("VALID", "新 IP 符合要求");
        } else {
            log("WARN", "新 IP 仍然不符合要求，需要等待或再次尝试");
        }
    } else {
        log("CHANGE", "更换请求已发送（API 未返回新 IP）");
    }

    $done();
}

run();
