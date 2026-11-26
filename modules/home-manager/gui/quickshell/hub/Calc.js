.pragma library

// 安全な再帰下降パーサによる簡易電卓（eval を使わない）。
// 対応演算子: + - * / % ^ ** () 単項 +/- 小数
function evaluate(raw) {
    if (!raw || typeof raw !== "string") return null;
    var expr = raw.trim();
    if (expr.length === 0) return null;

    var tokens = [];
    var i = 0;
    while (i < expr.length) {
        var ch = expr[i];
        if (ch === " " || ch === "\t") {
            i++;
            continue;
        }
        if ((ch >= "0" && ch <= "9") || ch === ".") {
            var start = i;
            var dotCount = 0;
            while (i < expr.length && ((expr[i] >= "0" && expr[i] <= "9") || expr[i] === ".")) {
                if (expr[i] === ".") dotCount++;
                if (dotCount > 1) return null;
                i++;
            }
            var numStr = expr.slice(start, i);
            if (numStr === ".") return null;
            var val = parseFloat(numStr);
            if (isNaN(val)) return null;
            tokens.push({ type: "num", value: val });
            continue;
        }
        if (ch === "*" && i + 1 < expr.length && expr[i + 1] === "*") {
            tokens.push({ type: "op", value: "^" });
            i += 2;
            continue;
        }
        if ("+-*/%^()".indexOf(ch) !== -1) {
            tokens.push({ type: "op", value: ch });
            i++;
            continue;
        }
        return null;
    }
    if (tokens.length === 0) return null;

    var pos = 0;
    function peek() { return pos < tokens.length ? tokens[pos] : null; }
    function next() { return tokens[pos++]; }

    function parseExpr() {
        var left = parseTerm();
        if (left === null) return null;
        while (peek() && peek().type === "op" && (peek().value === "+" || peek().value === "-")) {
            var op = next().value;
            var right = parseTerm();
            if (right === null) return null;
            left = (op === "+") ? (left + right) : (left - right);
        }
        return left;
    }

    function parseTerm() {
        var left = parsePower();
        if (left === null) return null;
        while (peek() && peek().type === "op" && (peek().value === "*" || peek().value === "/" || peek().value === "%")) {
            var op = next().value;
            var right = parsePower();
            if (right === null) return null;
            if (op === "*") left = left * right;
            else if (op === "/") {
                if (right === 0) return null;
                left = left / right;
            } else {
                if (right === 0) return null;
                left = left % right;
            }
        }
        return left;
    }

    function parsePower() {
        var base = parseUnary();
        if (base === null) return null;
        if (peek() && peek().type === "op" && peek().value === "^") {
            next();
            var exp = parsePower();
            if (exp === null) return null;
            return Math.pow(base, exp);
        }
        return base;
    }

    function parseUnary() {
        if (peek() && peek().type === "op" && (peek().value === "+" || peek().value === "-")) {
            var op = next().value;
            var v = parseUnary();
            if (v === null) return null;
            return op === "-" ? -v : v;
        }
        return parsePrimary();
    }

    function parsePrimary() {
        var tok = peek();
        if (!tok) return null;
        if (tok.type === "num") {
            next();
            return tok.value;
        }
        if (tok.type === "op" && tok.value === "(") {
            next();
            var inner = parseExpr();
            if (inner === null) return null;
            if (!peek() || peek().type !== "op" || peek().value !== ")") return null;
            next();
            return inner;
        }
        return null;
    }

    var result = parseExpr();
    if (result === null || pos !== tokens.length || !isFinite(result)) return null;
    // 浮動小数点誤差（0.1 + 0.2 等）を整える
    var rounded = Math.round(result * 1e10) / 1e10;
    return String(rounded);
}
