const arg = JSON.parse($argument);
const CHECK_URL = arg.check;
const CHANGE_URL = arg.change;
const REQUIRED_PREFIX = arg.prefix;

const TIMEOUT = 55000; // 55秒

function log(type, msg) {
    const ts = new Date().toISOString().replace("T"," ").split(".")[0];
    console.log(`[${ts}] [${type}] ${msg}`);
}

function valid_ip(ip) {
    return /^(\d{1,3}\.){3}\d{1,3}$/.test(ip);
}

function get_ip(url) {
    return new Promise((resolve) => {
        $httpClient.get({ url, timeout: TIMEOUT }, (err, resp, data) => {
            if (err || !data) {
                log("ERROR", "API 调用失败");
                resolve("");
            } else {
                resolve(data.trim());
            }
        });
    });
}

(async () => {

    let current_ip = await get_ip(CHECK_URL);
    if (!valid_ip(current_ip)) {
        log("ERROR", `查询失败或无效返回: ${current_ip || "nil"}`);
        return $done();
    }

    log("CHECK", `当前 IP: ${current_ip}`);

    if (current_ip.startsWith(REQUIRED_PREFIX)) {
        log("VALID", `IP 符合要求 (${REQUIRED_PREFIX})`);
        return $done();
    }

    log("INVALID", "IP 不符合要求 → 执行更换");

    let new_ip = await get_ip(CHANGE_URL);
    if (new_ip && valid_ip(new_ip)) {
        log("CHANGE", `更换完成: ${new_ip}`);

        if (new_ip.startsWith(REQUIRED_PREFIX)) {
            log("VALID", "新 IP 符合要求");
        } else {
            log("WARN", "新 IP 不符合要求");
        }
    } else {
        log("CHANGE", "更换已触发（API 无返回）");
    }

    $done();
})();
