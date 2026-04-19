// NetworkService.ets - 浙江大学教务系统网络服务
// Exports: setCookies, getCookies, setStudentId, getStudentId, isLoggedIn, login, getSsoLoginUrl,
//          fetchStudentInfo, fetchSemesters, fetchGrades, fetchCourseSchedule, fetchExams, fetchTodos,
//          fetchPaymentCode, checkUpdate, extractTicketFromCookies

import http from '@ohos.net.http';
import { Course, CourseTimeSlot, Exam, Todo } from '../model/Course';
import { Semester } from '../model/Semester';

// ============= API 基础配置 =============
// 浙江大学本科生院教务系统
export const BASE_SSO = 'https://zdbk.zju.edu.cn';
export const BASE_JW = 'https://zdbk.zju.edu.cn';
export const BASE_ECARD = 'https://ecard.zju.edu.cn';
export const CAS_BASE = 'https://zjuam.zju.edu.cn/cas';

// DNS 说明：不再强制指定公网 DNS，使用系统默认 DNS
// 在校内网环境下，系统默认 DNS（校内 DNS）能正确解析校内域名
// 强制使用公网 DNS 反而可能导致校内域名解析到错误 IP，造成连接超时

export interface LoginResult {
  success: boolean;
  message: string;
  cookies: string;
  isGrs: boolean;
}

export interface FetchResult<T> {
  success: boolean;
  data?: T;
  message: string;
}

interface GradesResponse {
  items?: Array<Record<string, Object>>;
  rows?: Array<Record<string, Object>>;
}

interface ExamsResponse {
  items?: Array<Record<string, Object>>;
  rows?: Array<Record<string, Object>>;
}

interface TodosResponse {
  items?: Array<Record<string, Object>>;
  rows?: Array<Record<string, Object>>;
}

// ============= Cookie 管理 =============
let savedCookies: string = '';
let savedStudentId: string = '';

export function setCookies(cookies: string): void {
  savedCookies = cookies;
}

export function getCookies(): string {
  return savedCookies;
}

export function setStudentId(id: string): void {
  savedStudentId = id;
}

export function getStudentId(): string {
  return savedStudentId;
}

export function isLoggedIn(): boolean {
  return savedCookies.length > 0;
}

// ============= Cookie 工具函数 =============

/**
 * 解析单条 cookie 字符串，提取 name=value 部分并加入 map
 */
function parseCookieLine(line: string, cookieMap: Map<string, string>, cookieAttrNames: Set<string>): void {
  const segment = line.trim().split(';')[0].trim(); // 只取第一段 name=value
  const eqIdx = segment.indexOf('=');
  if (eqIdx > 0) {
    const name = segment.substring(0, eqIdx).trim();
    const val = segment.substring(eqIdx + 1).trim();
    if (name.length > 0 && !cookieAttrNames.has(name.toLowerCase())) {
      cookieMap.set(name, val);
    }
  }
}

/**
 * 从 HttpResponse 中提取干净的 name=value 形式 cookie。
 * HarmonyOS response.cookies 可能包含 Path/Domain/Expires 等属性，
 * 直接用作 Cookie: 请求头会导致服务端认证失败。
 */
function extractCookieMap(resp: http.HttpResponse): Map<string, string> {
  const cookieMap = new Map<string, string>();
  // Cookie 属性名，不作为 cookie name 处理
  const cookieAttrNames = new Set<string>([
    'path', 'domain', 'expires', 'max-age', 'samesite', 'secure', 'httponly'
  ]);

  // 1. 解析 response.cookies（可能是 Set-Cookie 原始格式，按逗号或换行分隔）
  const cookiesField = resp.cookies as string ?? '';
  if (cookiesField.length > 0) {
    for (const line of cookiesField.split(/[,\n]/)) {
      parseCookieLine(line, cookieMap, cookieAttrNames);
    }
  }

  // 2. 解析 response.header 中的 set-cookie（作为补充/优先覆盖）
  const headers = resp.header as Record<string, Object>;
  for (const key of ['set-cookie', 'Set-Cookie', 'SET-COOKIE']) {
    if (headers[key]) {
      const raw = headers[key];
      const values: string[] = Array.isArray(raw) ? raw as string[] : [raw as string];
      for (const v of values) {
        for (const part of (v as string).split(',')) {
          parseCookieLine(part, cookieMap, cookieAttrNames);
        }
      }
      break;
    }
  }

  return cookieMap;
}

function cookieMapToString(map: Map<string, string>): string {
  const parts: string[] = [];
  map.forEach((val, name) => parts.push(`${name}=${val}`));
  return parts.join('; ');
}

function mergeCookieMaps(base: Map<string, string>, update: Map<string, string>): Map<string, string> {
  const result = new Map<string, string>(base);
  update.forEach((val, name) => result.set(name, val));
  return result;
}

// ============= 通用 HTTP 请求 =============

/**
 * cookieOverride: 若提供则替代 savedCookies（用于登录流程中间步骤）
 */
async function httpGet(url: string, extraHeaders?: Record<string, string>,
  cookieOverride?: string, timeoutMs: number = 15000): Promise<http.HttpResponse> {
  const request = http.createHttp();
  try {
    const cookieStr = cookieOverride !== undefined ? cookieOverride : savedCookies;
    const headers: Record<string, string> = {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Accept': 'application/json, text/plain, */*',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      'Accept-Encoding': 'gzip, deflate, br',
      'Connection': 'keep-alive'
    };
    if (cookieStr.length > 0) {
      headers['Cookie'] = cookieStr;
    }
    if (extraHeaders) {
      for (const key of Object.keys(extraHeaders)) {
        headers[key] = extraHeaders[key];
      }
    }
    console.info(`[httpGet] Requesting: ${url}`);
    const response = await request.request(url, {
      method: http.RequestMethod.GET,
      header: headers,
      connectTimeout: timeoutMs,
      readTimeout: timeoutMs,
      usingCache: false
      // 注意：不指定 dnsServers，使用系统默认 DNS
      // 在校内网环境下，系统默认 DNS（校内 DNS）能正确解析校内域名
      // 指定公网 DNS 反而可能导致校内域名解析错误
    });
    console.info(`[httpGet] Response: ${response.responseCode}, length=${(response.result as string)?.length ?? 0}`);
    return response;
  } catch (err) {
    console.error(`[httpGet] Failed: ${url}, error: ${(err as Error).message}`);
    throw new Error(`httpGet failed: ${(err as Error).message}`);
  } finally {
    request.destroy();
  }
}

async function httpPost(url: string, body: string,
  contentType: string = 'application/x-www-form-urlencoded',
  extraHeaders?: Record<string, string>,
  cookieOverride?: string, timeoutMs: number = 15000): Promise<http.HttpResponse> {
  const request = http.createHttp();
  try {
    const cookieStr = cookieOverride !== undefined ? cookieOverride : savedCookies;
    const headers: Record<string, string> = {
      'Content-Type': contentType,
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Accept': 'application/json, text/plain, */*',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      'Accept-Encoding': 'gzip, deflate, br',
      'Cache-Control': 'no-cache',
      'Pragma': 'no-cache'
    };
    if (cookieStr.length > 0) {
      headers['Cookie'] = cookieStr;
    }
    if (extraHeaders) {
      for (const key of Object.keys(extraHeaders)) {
        headers[key] = extraHeaders[key];
      }
    }
    // HarmonyOS http 模块要求 extraData 非空字符串，空字符串会引发 Parameter error
    const requestBody = body.length > 0 ? body : '_=1';
    console.info(`[httpPost] Requesting: ${url}, body length: ${requestBody.length}`);
    const response = await request.request(url, {
      method: http.RequestMethod.POST,
      header: headers,
      extraData: requestBody,
      connectTimeout: timeoutMs,
      readTimeout: timeoutMs,
      usingCache: false
      // 注意：不指定 dnsServers，使用系统默认 DNS
    });
    console.info(`[httpPost] Response: ${response.responseCode}, length=${(response.result as string)?.length ?? 0}`);
    return response;
  } catch (err) {
    console.error(`[httpPost] Failed: ${url}, error: ${(err as Error).message}`);
    throw new Error(`httpPost failed: ${(err as Error).message}`);
  } finally {
    request.destroy();
  }
}

// ============= 登录（浙江大学统一身份认证 CAS） =============

const CAS_LOGIN_URL = `${CAS_BASE}/login`;
const CAS_PUBKEY_URL = `${CAS_BASE}/v2/getPubKey`;
export const JW_BASE = `${BASE_JW}/jwglxt`;

// SSO 跳转登录 URL（用于网页跳转方式）
// 注意：必须使用 login_ssologin.html（不是 slogin）
export function getSsoLoginUrl(): string {
  return `${CAS_LOGIN_URL}?service=${encodeURIComponent(JW_BASE + '/xtgl/login_ssologin.html')}`;
}

export interface StudentInfo {
  success: boolean;
  studentId: string;
  name: string;
  college: string;
  major: string;
  grade: string;
}

let cachedStudentInfo: StudentInfo | null = null;

export function getCachedStudentInfo(): StudentInfo | null {
  return cachedStudentInfo ?? null;
}

export function setCachedStudentInfo(info: StudentInfo | null): void {
  cachedStudentInfo = info;
}

/**
 * 从教务系统首页 HTML 中提取学生信息（学号、姓名、学院等）
 */
function extractStudentInfoFromHtml(html: string): StudentInfo | null {
  // 会话失效检测
  if (html.includes('name="execution"') || html.includes('cas/login')) {
    console.warn('[StudentInfo] Session invalid (login form detected)');
    return null;
  }

  let studentId = '';
  let name = '';
  let college = '';
  let major = '';
  let grade = '';

  // 提取学号
  const idPatterns = [
    /xh['"]?\s*[:=]\s*['"]([^'"]+)['"]/,
    /usercode['"]?\s*[:=]\s*['"]([^'"]+)['"]/,
    /xhdm['"]?\s*[:=]\s*['"]([^'"]+)['"]/,
    /studentId['"]?\s*[:=]\s*['"]([^'"]+)['"]/,
    /学号[：:]\s*([^<\s]+)/,
  ];
  for (const pattern of idPatterns) {
    const match = html.match(pattern);
    if (match && match[1] && match[1].length >= 6) {
      studentId = match[1];
      break;
    }
  }

  // 提取姓名：常见格式有 xm="张三"、userName="张三"、姓名：张三
  const namePatterns = [
    /xm['"]?\s*[:=]\s*['"]([^'"]+)['"]/i,
    /userName['"]?\s*[:=]\s*['"]([^'"]+)['"]/i,
    /姓名[：:]\s*([^<\s，,]+)/,
    /<span[^>]*>\s*([^<]{2,5})\s*<\/span>\s*<span[^>]*>\s*同学/,
    /欢迎您[,，]\s*([^<\s，,]{2,5})/,
  ];
  for (const pattern of namePatterns) {
    const match = html.match(pattern);
    if (match && match[1] && match[1].length >= 2 && match[1].length <= 10) {
      name = match[1].trim();
      break;
    }
  }

  // 提取学院：常见格式 yxmc="计算机学院"
  const collegePatterns = [
    /yxmc['"]?\s*[:=]\s*['"]([^'"]+)['"]/i,
    /学院[：:]\s*([^<\s]+)/,
    /院系[：:]\s*([^<\s]+)/,
    /所在学院[：:]\s*([^<\s]+)/,
  ];
  for (const pattern of collegePatterns) {
    const match = html.match(pattern);
    if (match && match[1] && match[1].length >= 4) {
      college = match[1].trim();
      break;
    }
  }

  // 提取专业
  const majorPatterns = [
    /zymc['"]?\s*[:=]\s*['"]([^'"]+)['"]/i,
    /专业[：:]\s*([^<\s]+)/,
  ];
  for (const pattern of majorPatterns) {
    const match = html.match(pattern);
    if (match && match[1] && match[1].length >= 4) {
      major = match[1].trim();
      break;
    }
  }

  // 提取年级
  const gradePatterns = [
    /njmc['"]?\s*[:=]\s*['"]([^'"]+)['"]/i,
    /年级[：:]\s*(\d{4})/,
  ];
  for (const pattern of gradePatterns) {
    const match = html.match(pattern);
    if (match && match[1]) {
      grade = match[1].trim();
      break;
    }
  }

  if (studentId.length > 0 || name.length > 0) {
    return { success: true, studentId, name, college, major, grade };
  }
  return null;
}

/**
 * 从教务系统获取学生信息（用于网页登录后获取实际学号）
 * 网页登录成功后，调用此接口获取真实学号
 *
 * 优先方案：从课表 API 响应中提取学号（xjh 字段），已验证可用。
 * 次优方案：从首页 HTML 中提取完整学生信息（学号、姓名、学院）。
 */
export async function fetchStudentInfo(): Promise<StudentInfo> {
  console.info('[StudentInfo] Starting fetchStudentInfo...');

  // 如果已经有完整缓存，直接返回
  if (cachedStudentInfo && cachedStudentInfo.studentId.length > 0) {
    console.info(`[StudentInfo] Using cached info: ${cachedStudentInfo.studentId}`);
    return cachedStudentInfo;
  }

  try {
    // ═══════════════════════════════════════════════════════
    // 优先方案：从课表 API 获取学号
    // ZJU 正方系统的课表接口会返回当前登录人的学号（xh 字段），
    // 且响应为标准 JSON，无需解析 HTML，100% 可靠。
    // ═══════════════════════════════════════════════════════
    try {
      const now = new Date();
      const year = now.getFullYear();
      const month = now.getMonth() + 1;
      const term = month >= 9 ? '3' : '12';
      const yearStr = month >= 9 ? `${year}-${year + 1}` : `${year - 1}-${year}`;

      const body = `xnm=${encodeURIComponent(yearStr)}&xqm=${encodeURIComponent(term)}&captcha_value=`;
      const url = `${JW_BASE}/kbcx/xskbcx_cxXsKb.html`;
      console.info(`[StudentInfo] Trying timetable API: ${url}, body: ${body}`);

      const resp = await httpPost(url, body, 'application/x-www-form-urlencoded', {
        'X-Requested-With': 'XMLHttpRequest',
        'Referer': `${JW_BASE}/kbcx/xskbcx_cxXskbcxIndex.html`
      });

      if (resp.responseCode === 200) {
        const raw = resp.result as string;
        if (!raw.trimStart().startsWith('<')) {
          try {
            const data = JSON.parse(raw) as CourseScheduleResponseWithId;
            const studentId = (data.xh as string) ?? '';
            if (studentId.length > 0) {
              savedStudentId = studentId;
              console.info(`[StudentInfo] Extracted from timetable API: ${studentId}`);
            }
          } catch {
            console.warn('[StudentInfo] Timetable response JSON parse failed');
          }
        } else {
          console.warn('[StudentInfo] Timetable API returned HTML (session invalid)');
        }
      }
    } catch (e) {
      console.warn(`[StudentInfo] Timetable API failed: ${(e as Error).message}, continuing to HTML fallback...`);
    }

    // ═══════════════════════════════════════════════════════
    // 次优方案：从首页 HTML 提取完整学生信息
    // ═══════════════════════════════════════════════════════
    try {
      console.info('[StudentInfo] Trying index page HTML for full info...');
      const indexUrl = `${JW_BASE}/xtgl/index_initMenu.html?gnmkdm=N300001&layout=default`;
      const htmlResp = await httpGet(indexUrl, undefined, undefined, 5000);
      console.info(`[StudentInfo] Index page response code: ${htmlResp.responseCode}`);

      if (htmlResp.responseCode === 200) {
        const html = htmlResp.result as string;
        const info = extractStudentInfoFromHtml(html);
        if (info) {
          if (info.studentId.length > 0) {
            savedStudentId = info.studentId;
          } else if (savedStudentId.length > 0) {
            info.studentId = savedStudentId;
          }
          cachedStudentInfo = info;
          console.info(`[StudentInfo] Found from HTML: id=${info.studentId}, name=${info.name}, college=${info.college}`);
          return info;
        }
      }
    } catch (e) {
      console.warn(`[StudentInfo] Index page failed: ${(e as Error).message}`);
    }

    // ═══════════════════════════════════════════════════════
    // 兜底：只返回学号
    // ═══════════════════════════════════════════════════════
    if (savedStudentId.length > 0) {
      const fallback: StudentInfo = { success: true, studentId: savedStudentId, name: '', college: '', major: '', grade: '' };
      cachedStudentInfo = fallback;
      return fallback;
    }

    console.warn('[StudentInfo] All methods failed');
    return { success: false, studentId: '', name: '', college: '', major: '', grade: '' };
  } catch (e) {
    console.error(`[StudentInfo] Unexpected error: ${(e as Error).message}`);
    if (savedStudentId.length > 0) {
      return { success: true, studentId: savedStudentId, name: '', college: '', major: '', grade: '' };
    }
    return { success: false, studentId: '', name: '', college: '', major: '', grade: '' };
  }
}

/**
 * 从 Cookie 字符串中提取 iPlanetDirectoryPro 值
 */
export function extractTicketFromCookies(cookieStr: string): string {
  const parts = cookieStr.split(';');
  for (const part of parts) {
    const trimmed = part.trim();
    if (trimmed.startsWith('iPlanetDirectoryPro=')) {
      return trimmed.substring('iPlanetDirectoryPro='.length).split(';')[0];
    }
  }
  return '';
}

// ============= RSA 加密工具函数 =============

/** 将十六进制字符串转为 BigInt */
const hexToBigInt = (hex: string): bigint => BigInt('0x' + hex);

/** 模幂运算: (base^exp) % mod */
const modPow = (base: bigint, exp: bigint, mod: bigint): bigint => {
  let result = 1n;
  base = base % mod;
  let e = exp;
  let b = base;
  while (e > 0n) {
    if (e % 2n === 1n) {
      result = (result * b) % mod;
    }
    e = e / 2n;
    b = (b * b) % mod;
  }
  return result;
};

/**
 * RSA 加密（ZJU CAS zjuam.dart 兼容实现）
 * 密码直接 UTF-8 编码为 hex，与 Flutter 实现完全一致
 */
function rsaEncryptForCas(plaintext: string, modulusHex: string, exponentHex: string): string {
  try {
    const n = hexToBigInt(modulusHex);
    const e = hexToBigInt(exponentHex);

    // 将密码转为 UTF-8 hex（与 Flutter utf8.encode 一致）
    let pwdHex = '';
    for (let i = 0; i < plaintext.length; i++) {
      const code = plaintext.charCodeAt(i);
      if (code < 0x80) {
        // ASCII: 单字节
        pwdHex += code.toString(16).padStart(2, '0');
      } else if (code < 0x800) {
        // 2字节 UTF-8: 0xC0 | (code >> 6), 0x80 | (code & 0x3F)
        pwdHex += (0xC0 | (code >> 6)).toString(16).padStart(2, '0');
        pwdHex += (0x80 | (code & 0x3F)).toString(16).padStart(2, '0');
      } else {
        // 3字节 UTF-8: 0xE0 | (code >> 12), ...
        pwdHex += (0xE0 | (code >> 12)).toString(16).padStart(2, '0');
        pwdHex += (0x80 | ((code >> 6) & 0x3F)).toString(16).padStart(2, '0');
        pwdHex += (0x80 | (code & 0x3F)).toString(16).padStart(2, '0');
      }
    }
    const pwdNum = hexToBigInt(pwdHex);

    // RSA 加密: cipher = plaintext^exponent mod modulus
    const encrypted = modPow(pwdNum, e, n);

    // 补齐到 128 hex 字符（512-bit RSA 密钥）
    const result = encrypted.toString(16).padStart(128, '0');
    console.info(`[RSA] Encrypted password, result length: ${result.length}`);
    console.info(`[RSA] modulus: ${modulusHex.substring(0, 32)}..., exponent: ${exponentHex}`);
    return result;
  } catch (err) {
    console.error(`[RSA] Encryption failed: ${(err as Error).message}`);
    // 加密失败时返回空字符串，让调用方处理
    return '';
  }
}

/**
 * 使用 CAS 的 iPlanetDirectoryPro 换取 JW 系统会话（JSESSIONID + route）
 * 供账号密码登录和网页登录共同使用。
 */
export async function exchangeCasForJwSession(iplanet: string): Promise<string | null> {
  try {
    const serviceUrl = `${JW_BASE}/xtgl/login_ssologin.html`;
    const casServiceUrl = `${CAS_LOGIN_URL}?service=${encodeURIComponent(serviceUrl)}`;
    const jwResp = await httpGet(casServiceUrl, undefined, `iPlanetDirectoryPro=${iplanet}`);
    console.info(`[exchangeCasForJwSession] JW response code: ${jwResp.responseCode}`);

    const jwCookieMap = extractCookieMap(jwResp);
    console.info(`[exchangeCasForJwSession] JW cookies: ${cookieMapToString(jwCookieMap).substring(0, 150)}`);

    const jsessionid = jwCookieMap.get('JSESSIONID') ?? '';
    const route = jwCookieMap.get('route') ?? '';

    if (jsessionid.length > 0) {
      return route.length > 0
        ? `JSESSIONID=${jsessionid}; route=${route}`
        : `JSESSIONID=${jsessionid}`;
    } else if (route.length > 0) {
      return `route=${route}; iPlanetDirectoryPro=${iplanet}`;
    } else {
      console.warn('[exchangeCasForJwSession] JSESSIONID not found, using all accumulated cookies');
      return cookieMapToString(jwCookieMap);
    }
  } catch (err) {
    console.error(`[exchangeCasForJwSession] Failed: ${(err as Error).message}`);
    return null;
  }
}

export async function login(studentId: string, password: string): Promise<LoginResult> {
  try {
    const jwServiceUrl = `${JW_BASE}/xtgl/login_ssologin.html`;
    const casLoginWithService = `${CAS_LOGIN_URL}?service=${encodeURIComponent(jwServiceUrl)}`;

    // Step 1: GET cas/login?service=... (带 service，让 CAS 登录成功后直接跳到教务系统)
    console.info(`[Login] Step1: GET ${casLoginWithService}`);
    const casPageResp = await httpGet(casLoginWithService, undefined, '');
    console.info(`[Login] Step1 response: ${casPageResp.responseCode}`);
    if (casPageResp.responseCode !== 200) {
      return { success: false, message: `无法连接认证服务器 (${casPageResp.responseCode})`, cookies: '', isGrs: false };
    }

    let casCookieMap = extractCookieMap(casPageResp);
    const casCookieStr = cookieMapToString(casCookieMap);
    console.info(`[Login] Step1 OK, CAS cookies: ${casCookieStr.substring(0, 80)}`);

    // Step 2: 获取 RSA 公钥
    let modulus = '';
    let exponent = '';
    console.info(`[Login] Step2: GET RSA pubkey`);
    try {
      const pubkeyResp = await httpGet(CAS_PUBKEY_URL, undefined, casCookieStr);
      if (pubkeyResp.responseCode === 200) {
        const pubkeyJson = JSON.parse(pubkeyResp.result as string) as Record<string, string>;
        modulus = pubkeyJson['modulus'] ?? '';
        exponent = pubkeyJson['exponent'] ?? '';
      }
    } catch (e) {
      console.warn(`[Login] RSA key fetch failed: ${(e as Error).message}`);
    }

    // Step 3: 解析 execution token
    const pageHtml = casPageResp.result as string;
    let execution = '';
    const inputTagMatch = pageHtml.match(/<input[^>]+name=["']execution["'][^>]*>/i);
    if (inputTagMatch) {
      const valMatch = inputTagMatch[0].match(/value=["']([^"']+)["']/i);
      if (valMatch) execution = valMatch[1];
    }
    if (!execution) {
      const m2 = pageHtml.match(/value="([^"]+)"[^>]*name="execution"/i);
      if (m2) execution = m2[1];
    }
    if (!execution) {
      const m3 = pageHtml.match(/name="execution"\s[^>]*value="([^"]+)"/);
      if (m3) execution = m3[1];
    }
    if (!execution) {
      return { success: false, message: '获取认证参数失败，请稍后重试', cookies: '', isGrs: false };
    }

    // Step 3b: RSA 加密密码
    let encryptedPassword = '';
    if (modulus.length > 0 && exponent.length > 0) {
      encryptedPassword = rsaEncryptForCas(password, modulus, exponent);
    }
    if (!encryptedPassword || encryptedPassword.length === 0) {
      return { success: false, message: '密码加密失败，请稍后重试', cookies: '', isGrs: false };
    }

    // Step 4: POST cas/login?service=...
    // CAS 成功后会 302 跳到 jwServiceUrl，@ohos.net.http 自动跟随后
    // 最终响应来自 zdbk.zju.edu.cn，可能直接携带 JSESSIONID + route
    const formData = `username=${encodeURIComponent(studentId)}&password=${encodeURIComponent(encryptedPassword)}&execution=${encodeURIComponent(execution)}&_eventId=submit&rememberMe=true`;
    const authResp = await httpPost(casLoginWithService, formData, 'application/x-www-form-urlencoded', {
      'Referer': casLoginWithService,
      'Origin': 'https://zjuam.zju.edu.cn'
    }, casCookieStr);

    const authHtml = authResp.result as string;
    console.info(`[Login] Step4 POST response code: ${authResp.responseCode}`);

    const authCookieMap = mergeCookieMaps(casCookieMap, extractCookieMap(authResp));

    // 优先：如果自动跟随到了教务系统，直接拿到 JW cookies
    const jsessionid = authCookieMap.get('JSESSIONID') ?? '';
    const route = authCookieMap.get('route') ?? '';

    if (jsessionid.length > 0) {
      const jwCookies = route.length > 0
        ? `JSESSIONID=${jsessionid}; route=${route}`
        : `JSESSIONID=${jsessionid}`;
      savedCookies = jwCookies;
      savedStudentId = studentId;
      const isGrs = studentId.toUpperCase().startsWith('G');
      console.info(`[Login] Login success via direct redirect! studentId: ${studentId}, isGrs: ${isGrs}`);
      return { success: true, message: '登录成功', cookies: savedCookies, isGrs };
    }

    // 如果页面仍是登录表单，说明密码错误
    if (typeof authHtml === 'string' && authHtml.includes('name="execution"')) {
      let errorMsg = '用户名或密码错误';
      const errMatch = authHtml.match(/id="errormsg"[^>]*>([^<]+)</);
      if (errMatch && errMatch[1].trim().length > 0) errorMsg = errMatch[1].trim();
      else {
        const errMatch2 = authHtml.match(/class="msg-error"[^>]*>([^<]+)</);
        if (errMatch2 && errMatch2[1].trim().length > 0) errorMsg = errMatch2[1].trim();
      }
      return { success: false, message: errorMsg, cookies: '', isGrs: false };
    }

    // 兜底：尝试从中间响应里找 iPlanetDirectoryPro，再手动换取 JW 会话
    const iplanet = authCookieMap.get('iPlanetDirectoryPro') ?? '';
    console.info(`[Login] iPlanetDirectoryPro length: ${iplanet.length}`);

    if (iplanet.length === 0) {
      console.warn(`[Login] No JW cookies and no iPlanetDirectoryPro. All cookies: ${cookieMapToString(authCookieMap).substring(0, 200)}`);
      return { success: false, message: '登录失败，未获取到教务系统会话', cookies: '', isGrs: false };
    }

    const jwCookies = await exchangeCasForJwSession(iplanet);
    if (!jwCookies || jwCookies.length === 0) {
      return { success: false, message: '登录失败，无法获取教务系统会话', cookies: '', isGrs: false };
    }

    savedCookies = jwCookies;
    savedStudentId = studentId;
    const isGrs = studentId.toUpperCase().startsWith('G');
    console.info(`[Login] Login success! studentId: ${studentId}, isGrs: ${isGrs}`);
    return { success: true, message: '登录成功', cookies: savedCookies, isGrs };

  } catch (err) {
    const error = err as Error;
    let errorMsg = `网络错误: ${error.message}`;
    if (error.message.includes('resolve') || error.message.includes('dns')) errorMsg = '无法解析域名，请检查网络连接';
    else if (error.message.includes('timeout')) errorMsg = '请求超时，请稍后重试';
    return { success: false, message: errorMsg, cookies: '', isGrs: false };
  }
}

// ============= 获取学业数据 =============

export async function fetchSemesters(): Promise<FetchResult<Semester[]>> {
  try {
    console.info(`[NetworkService] Fetching semesters...`);

    // ═══════════════════════════════════════════════════════
    // 方案 1: ZJU 专用学期查询接口（最可靠）
    // POST /tjxl/tjcx_cxXnxqgl.html 返回 {items: [{xnm, xqm, xnmc}]} 格式
    // 使用 6 秒短超时：校外网此接口必然超时，不必等待默认 15 秒
    // ═══════════════════════════════════════════════════════
    try {
      const resp = await httpPost(
        `${JW_BASE}/tjxl/tjcx_cxXnxqgl.html?doType=query`,
        `_=1`,
        'application/x-www-form-urlencoded',
        { 'X-Requested-With': 'XMLHttpRequest' },
        undefined,
        6000
      );

      if (resp.responseCode === 200) {
        const raw = resp.result as string;
        if (!raw.trimStart().startsWith('<')) {
          const semesters = parseSemestersFromJson(raw);
          if (semesters.length > 0) {
            console.info(`[NetworkService] Got ${semesters.length} semesters from API`);
            return { success: true, data: semesters, message: '获取成功' };
          }
        }
      }
      console.warn(`[NetworkService] Semester API returned HTTP ${resp.responseCode} or empty`);
    } catch (e) {
      console.warn(`[NetworkService] Semester API failed: ${(e as Error).message}`);
    }

    // ═══════════════════════════════════════════════════════
    // 方案 2: 从课表页 HTML 提取学期下拉框
    // 使用 6 秒短超时
    // ═══════════════════════════════════════════════════════
    const htmlResp = await httpGet(`${JW_BASE}/kbcx/xskbcx_cxXskbcxIndex.html?gnmkdm=N2151&layout=default`, undefined, undefined, 6000);
    if (htmlResp.responseCode === 200) {
      const semesters = parseSemestersFromHtml(htmlResp.result as string);
      if (semesters.length > 0) {
        console.info(`[NetworkService] Got ${semesters.length} semesters from HTML`);
        return { success: true, data: semesters, message: '获取成功' };
      }
    }

    // ═══════════════════════════════════════════════════════
    // 方案 3: 按当前日期自动生成（兜底）
    // 根据学年规则：从大一入学到现在，推算所有在校学期
    // ═══════════════════════════════════════════════════════
    const fallback = generateSemestersByDate();
    console.warn(`[NetworkService] Using date-based fallback: ${fallback.length} semesters`);
    return { success: true, data: fallback, message: '获取成功（兜底）' };
  } catch (err) {
    const error = err as Error;
    console.error(`[NetworkService] Fetch semesters error: ${error.message}`);
    const fallback = generateSemestersByDate();
    return { success: true, data: fallback, message: '获取成功（兜底）' };
  }
}

export async function fetchGrades(semesterId: string, timeoutMs?: number): Promise<FetchResult<Course[]>> {
  const maxRetries = timeoutMs !== undefined && timeoutMs <= 10000 ? 0 : 2;

  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      const yearTerm = parseSemesterId(semesterId);
      const year = yearTerm[0];
      const term = yearTerm[1];

      // 与 Celechron zdbk.dart.getTranscript 一致：不带学期参数可获取全部，但为避免数据过多，按学期查询
      const body = `xnm=${encodeURIComponent(year)}&xqm=${encodeURIComponent(term)}&_search=false&nd=${Date.now()}&queryModel.showCount=5000&queryModel.currentPage=1&queryModel.sortName=&queryModel.sortOrder=asc&time=0`;
      const url = `${JW_BASE}/cxdy/xscjcx_cxXscjIndex.html?doType=query`;
      console.info(`[NetworkService] Fetching grades, attempt ${attempt + 1}, xnm=${year}, xqm=${term}`);

      const resp = await httpPost(url, body, 'application/x-www-form-urlencoded', {
        'X-Requested-With': 'XMLHttpRequest',
        'Referer': `${JW_BASE}/cxdy/xscjcx_cxXscjIndex.html`
      }, undefined, timeoutMs);

      if (resp.responseCode !== 200) {
        console.warn(`[NetworkService] Grades response code: ${resp.responseCode}`);
        if (resp.responseCode === 302 || resp.responseCode === 301) {
          return { success: false, message: '会话已失效，请重新登录' };
        }
        return { success: false, message: `获取成绩失败 (${resp.responseCode})` };
      }

      const raw = resp.result as string;
      if (raw.trimStart().startsWith('<')) {
        console.warn(`[NetworkService] Grades returned HTML (session invalid?), length=${raw.length}`);
        return { success: false, message: '成绩接口返回异常（会话可能已失效）' };
      }

      const courses = parseGradesFromJson(raw);
      console.info(`[NetworkService] Parsed ${courses.length} grade records for ${semesterId}`);
      return { success: true, data: courses, message: '获取成功' };
    } catch (err) {
      const errorMsg = (err as Error).message;
      console.warn(`[NetworkService] Fetch grades attempt ${attempt + 1} failed: ${errorMsg}`);

      if (attempt === maxRetries) {
        return { success: false, message: `网络错误: ${errorMsg}` };
      }

      // 重试前等待一下
      await new Promise<void>((resolve) => setTimeout(resolve, 2000));
    }
  }

  return { success: false, message: '获取成绩失败' };
}

export async function fetchCourseSchedule(semesterId: string, timeoutMs?: number): Promise<FetchResult<Course[]>> {
  const maxRetries = timeoutMs !== undefined && timeoutMs <= 10000 ? 0 : 2;

  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      const yearTerm = parseSemesterId(semesterId);
      const year = yearTerm[0];
      const term = yearTerm[1];
      const body = `xnm=${encodeURIComponent(year)}&xqm=${encodeURIComponent(term)}&captcha_value=`;
      const url = `${JW_BASE}/kbcx/xskbcx_cxXsKb.html`;
      console.info(`[NetworkService] Fetching schedule, attempt ${attempt + 1}, xnm=${year}, xqm=${term}`);

      const resp = await httpPost(url, body, 'application/x-www-form-urlencoded', {
        'X-Requested-With': 'XMLHttpRequest',
        'Referer': `${JW_BASE}/kbcx/xskbcx_cxXskbcxIndex.html`
      }, undefined, timeoutMs);
      console.info(`[NetworkService] Schedule response code: ${resp.responseCode}`);

      if (resp.responseCode !== 200) {
        return { success: false, message: `获取课表失败 (${resp.responseCode})` };
      }

      const raw = resp.result as string;
      console.info(`[NetworkService] Schedule raw length: ${raw.length}`);

      if (raw === 'null' || raw.trim() === '') {
        console.warn('[NetworkService] Schedule returned null or empty');
        return { success: true, data: [], message: '获取成功（无课表）' };
      }

      const courses = parseCourseScheduleFromJson(raw, semesterId);
      return { success: true, data: courses, message: '获取成功' };
    } catch (err) {
      const errorMsg = (err as Error).message;
      console.warn(`[NetworkService] Fetch schedule attempt ${attempt + 1} failed: ${errorMsg}`);

      if (attempt === maxRetries) {
        return { success: false, message: `网络错误: ${errorMsg}` };
      }

      await new Promise<void>((resolve) => setTimeout(resolve, 2000));
    }
  }

  return { success: false, message: '获取课表失败' };
}

export async function fetchExams(semesterId: string, timeoutMs?: number): Promise<FetchResult<Exam[]>> {
  const maxRetries = timeoutMs !== undefined && timeoutMs <= 10000 ? 0 : 2;

  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      const yearTerm = parseSemesterId(semesterId);
      const year = yearTerm[0];
      const term = yearTerm[1];
      const body = `xnm=${year}&xqm=${term}&_search=false&nd=${Date.now()}&queryModel.showCount=5000&queryModel.currentPage=1&queryModel.sortName=&queryModel.sortOrder=asc`;
      console.info(`[NetworkService] Fetching exams, attempt ${attempt + 1}, xnm=${year}, xqm=${term}`);

      const resp = await httpPost(
        `${JW_BASE}/xskscx/kscx_cxXsgrksIndex.html?doType=query&queryModel.showCount=5000`, body,
        'application/x-www-form-urlencoded', {
          'X-Requested-With': 'XMLHttpRequest',
          'Referer': `${JW_BASE}/xskscx/kscx_cxXsgrksIndex.html`
        }, undefined, timeoutMs);

      if (resp.responseCode !== 200) {
        return { success: false, message: `获取考试失败 (${resp.responseCode})` };
      }

      const raw = resp.result as string;
      if (raw.trimStart().startsWith('<')) {
        return { success: false, message: '考试接口返回异常' };
      }

      const exams = parseExamsFromJson(raw, semesterId);
      return { success: true, data: exams, message: '获取成功' };
    } catch (err) {
      const errorMsg = (err as Error).message;
      console.warn(`[NetworkService] Fetch exams attempt ${attempt + 1} failed: ${errorMsg}`);

      if (attempt === maxRetries) {
        return { success: false, message: `网络错误: ${errorMsg}` };
      }

      await new Promise<void>((resolve) => setTimeout(resolve, 2000));
    }
  }

  return { success: false, message: '获取考试失败' };
}

export async function fetchTodos(semesterId: string, timeoutMs?: number): Promise<FetchResult<Todo[]>> {
  const maxRetries = timeoutMs !== undefined && timeoutMs <= 10000 ? 0 : 2;

  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      const yearTerm = parseSemesterId(semesterId);
      const year = yearTerm[0];
      const term = yearTerm[1];
      const body = `xnm=${year}&xqm=${term}&_search=false&nd=${Date.now()}&queryModel.showCount=200&queryModel.currentPage=1`;
      console.info(`[NetworkService] Fetching todos, attempt ${attempt + 1}`);

      const resp = await httpPost(
        `${JW_BASE}/xtgl/ywcx_cxWdyw.html?doType=query&gnmkdm=N400010&layout=default`, body,
        'application/x-www-form-urlencoded', { 'X-Requested-With': 'XMLHttpRequest' }, undefined, timeoutMs);

      if (resp.responseCode !== 200) {
        return { success: false, message: `获取作业失败 (${resp.responseCode})` };
      }

      const raw = resp.result as string;
      if (raw.trimStart().startsWith('<')) {
        return { success: false, message: '作业接口返回异常' };
      }

      const todos = parseTodosFromJson(raw, semesterId);
      return { success: true, data: todos, message: '获取成功' };
    } catch (err) {
      const errorMsg = (err as Error).message;
      console.warn(`[NetworkService] Fetch todos attempt ${attempt + 1} failed: ${errorMsg}`);

      if (attempt === maxRetries) {
        return { success: false, message: `网络错误: ${errorMsg}` };
      }

      await new Promise<void>((resolve) => setTimeout(resolve, 2000));
    }
  }

  return { success: false, message: '获取作业失败' };
}

// ============= 诊断用原始请求 =============

/** GET 请求并返回原始响应（供诊断页面使用） */
export async function fetchRawGet(url: string): Promise<FetchResult<string>> {
  try {
    const resp = await httpGet(url);
    return {
      success: resp.responseCode === 200,
      data: resp.result as string,
      message: `HTTP ${resp.responseCode}`
    };
  } catch (err) {
    return { success: false, message: (err as Error).message };
  }
}

/** 直接 POST 并返回原始响应（供诊断页面使用） */
export async function fetchRaw(url: string, body: string,
  extraHeaders?: Record<string, string>): Promise<FetchResult<string>> {
  try {
    const resp = await httpPost(url, body, 'application/x-www-form-urlencoded', extraHeaders);
    return {
      success: resp.responseCode === 200,
      data: resp.result as string,
      message: `HTTP ${resp.responseCode}`
    };
  } catch (err) {
    return { success: false, message: (err as Error).message };
  }
}

// ============= 付款码 =============

export async function fetchPaymentCode(): Promise<FetchResult<string>> {
  try {
    const resp = await httpGet(`${BASE_ECARD}/api/qrcode/get`);
    if (resp.responseCode !== 200) {
      return { success: false, message: `获取付款码失败 (${resp.responseCode})` };
    }
    const json = JSON.parse(resp.result as string) as Record<string, string | number>;
    const code = json['code'] as string ?? json['qrcode'] as string ?? '';
    return { success: true, data: code, message: '获取成功' };
  } catch (err) {
    const error = err as Error;
    return { success: false, message: `网络错误: ${error.message}` };
  }
}

// ============= 检查更新 =============

export async function checkUpdate(): Promise<FetchResult<string>> {
  try {
    const request = http.createHttp();
    const resp = await request.request(
      'https://api.github.com/repos/Celechron/Celechron/releases/latest',
      {
        method: http.RequestMethod.GET,
        header: { 'Accept': 'application/vnd.github.v3+json' },
        connectTimeout: 8000,
        readTimeout: 8000
      }
    );
    request.destroy();
    if (resp.responseCode !== 200) {
      return { success: false, message: '检查更新失败' };
    }
    const json = JSON.parse(resp.result as string) as Record<string, string>;
    const version = json['tag_name'] ?? '';
    return { success: true, data: version, message: '检查成功' };
  } catch {
    return { success: false, message: '检查更新失败' };
  }
}

// ============= 解析函数 =============

function parseSemesterId(semesterId: string): [string, string] {
  // semesterId 格式: "2023-2024-1" -> year="2023-2024", term="3"(第一学期=3, 第二学期=12)
  const parts = semesterId.split('-');
  if (parts.length >= 3) {
    const year = `${parts[0]}-${parts[1]}`;
    const termNum = parseInt(parts[2]);
    const term = termNum === 1 ? '3' : '12';
    return [year, term];
  }
  return ['2023-2024', '3'];
}

/**
 * 从 ZJU 学期接口返回的 JSON 中解析学期列表
 * 响应格式: {items: [{xnm: "2025-2026", xqm: "3", xnmc: "2025-2026学年第一学期"}, ...]}
 */
interface SemesterApiItem {
  xnm?: string;   // 学年，如 "2025-2026"
  xqm?: string;   // 学期代码，"3"=第一学期，"12"=第二学期
  xnmc?: string;  // 学期名称，如 "2025-2026学年第一学期"
}

interface SemesterApiResponse {
  items?: SemesterApiItem[];
  rows?: SemesterApiItem[];
}

function parseSemestersFromJson(json: string): Semester[] {
  try {
    const data = JSON.parse(json) as SemesterApiResponse;
    const items = data.items ?? data.rows ?? [];
    const semesters: Semester[] = [];

    for (const item of items) {
      const year = (item.xnm as string) ?? '';
      const term = (item.xqm as string) ?? '';
      const name = (item.xnmc as string) ?? `${year} 第${term === '3' ? '一' : '二'}学期`;

      if (!year || !term) continue;
      if (!/^\d{4}-\d{4}$/.test(year)) continue;

      const termNum = term === '3' ? 1 : 2;
      const yearStart = parseInt(year.split('-')[0]);
      const s = new Semester();
      s.id = `${year}-${termNum}`;
      s.name = name;
      // 估算学期起止日期（精确日期从系统获取，此处估算）
      s.startDate = new Date(termNum === 1 ? `${yearStart}-09-01` : `${yearStart + 1}-02-15`);
      s.endDate = new Date(termNum === 1 ? `${yearStart + 1}-01-31` : `${yearStart + 1}-07-31`);
      semesters.push(s);
    }

    // 按 id 升序排列（由远到近）
    semesters.sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
    return semesters;
  } catch {
    return [];
  }
}

/**
 * 根据当前日期自动生成学期列表（兜底方案）
 * 从大一入学（第1学年秋季）到现在，估算所有在校学期
 * 当前时间：2026年4月（2025-2026学年春季学期进行中）
 */
function generateSemestersByDate(): Semester[] {
  const now = new Date();
  const currentYear = now.getFullYear();
  const currentMonth = now.getMonth() + 1; // 1-12

  // 学年起始年：9月及之后为新学年（如 2025年9月 → 2025-2026学年）
  const currentAcademicYearStart = currentMonth >= 9 ? currentYear : currentYear - 1;

  // 假设大一入学年份（按当前时间估算，最多覆盖6年）
  // 研究生学制2年，本科4年 → 统一按4年计算（多覆盖2年）
  const freshmanYearStart = currentAcademicYearStart - 4;

  const semesters: Semester[] = [];

  for (let sy = freshmanYearStart; sy <= currentAcademicYearStart; sy++) {
    // 秋季学期（第一学期）
    const fallSem = new Semester();
    fallSem.id = `${sy}-${sy + 1}-1`;
    fallSem.name = `${sy}-${sy + 1} 第一学期`;
    fallSem.startDate = new Date(`${sy}-09-01`);
    fallSem.endDate = new Date(`${sy + 1}-01-31`);
    semesters.push(fallSem);

    // 春季学期（第二学期）
    const springSem = new Semester();
    springSem.id = `${sy}-${sy + 1}-2`;
    springSem.name = `${sy}-${sy + 1} 第二学期`;
    springSem.startDate = new Date(`${sy + 1}-02-15`);
    springSem.endDate = new Date(`${sy + 1}-07-31`);
    // 只添加当前学年之前（含当前学年春季，如果已到春季的话）
    const springYear = sy + 1;
    const isCurrentOrPastSpring = springYear < currentYear ||
      (springYear === currentYear && currentMonth >= 2);
    if (isCurrentOrPastSpring || sy < currentAcademicYearStart) {
      semesters.push(springSem);
    }
  }

  // 按 id 升序排列
  semesters.sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
  return semesters;
}

function parseSemestersFromHtml(html: string): Semester[] {
  const semesters: Semester[] = [];

  // 正方教务系统的学期选择器由两个 <select> 组成：
  //   <select name="xnm">  → 学年，option value 如 "2024-2025"
  //   <select name="xqm">  → 学期，option value "3"(第一学期) 或 "12"(第二学期)
  //
  // 注意：部分 ZJU 版本的正方系统通过 JS 动态加载下拉选项，
  // 静态 HTML 中 <select> 内容为空，需要从 JS 变量中提取。

  // ── 尝试方案 1: 标准 name= 属性匹配 ──
  let xnmBlock = html.match(/<select[^>]*name=["']?xnm["']?[^>]*>([\s\S]*?)<\/select>/i);
  let xqmBlock = html.match(/<select[^>]*name=["']?xqm["']?[^>]*>([\s\S]*?)<\/select>/i);

  // ── 尝试方案 2: id= 属性匹配（部分版本用 id 而非 name） ──
  if (!xnmBlock) {
    xnmBlock = html.match(/<select[^>]*id=["']?xnm["']?[^>]*>([\s\S]*?)<\/select>/i);
  }
  if (!xqmBlock) {
    xqmBlock = html.match(/<select[^>]*id=["']?xqm["']?[^>]*>([\s\S]*?)<\/select>/i);
  }

  const years: string[] = [];
  if (xnmBlock && xnmBlock[1]) {
    const optRe = /<option[^>]*value=["']?([^"'\s>]+)["']?[^>]*>/gi;
    let m: RegExpExecArray | null;
    while ((m = optRe.exec(xnmBlock[1])) !== null) {
      if (/^\d{4}-\d{4}$/.test(m[1])) {
        years.push(m[1]);
      }
    }
  }

  const terms: string[] = [];
  if (xqmBlock && xqmBlock[1]) {
    const optRe = /<option[^>]*value=["']?([^"'\s>]+)["']?[^>]*>/gi;
    let m: RegExpExecArray | null;
    while ((m = optRe.exec(xqmBlock[1])) !== null) {
      if (m[1] === '3' || m[1] === '12') {
        terms.push(m[1]);
      }
    }
  }

  // ── 尝试方案 3: 从嵌入的 JS 变量中提取学年列表 ──
  // 正方系统有时把学年列表写在 JS 里，如: var xnms = ["2024-2025","2023-2024"]
  if (years.length === 0) {
    const jsArrayRe = /["'](\d{4}-\d{4})["']/g;
    let m: RegExpExecArray | null;
    while ((m = jsArrayRe.exec(html)) !== null) {
      if (!years.includes(m[1])) {
        years.push(m[1]);
      }
    }
  }

  // ── 尝试方案 4: 旧格式 value="2023-2024-1" 的 option ──
  if (years.length === 0 || terms.length === 0) {
    const optRe = /<option[^>]*value=["']?(\d{4}-\d{4}-[12])["']?[^>]*>([^<]*)<\/option>/gi;
    let m: RegExpExecArray | null;
    while ((m = optRe.exec(html)) !== null) {
      const value = m[1];
      const label = m[2].trim();
      const s = new Semester();
      s.id = value;
      s.name = label.length > 0 ? label : value;
      const yearStart = parseInt(value.split('-')[0]);
      const isFirst = value.endsWith('-1');
      s.startDate = new Date(isFirst ? `${yearStart}-09-10` : `${yearStart + 1}-02-28`);
      s.endDate = new Date(isFirst ? `${yearStart + 1}-01-20` : `${yearStart + 1}-07-10`);
      semesters.push(s);
    }
    if (semesters.length > 0) {
      semesters.sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
      return semesters;
    }
  }

  if (years.length === 0) {
    // 所有方案均无法从 HTML 提取学期，返回空列表让调用方使用兜底方案
    return [];
  }

  // 若 terms 为空，默认包含两个学期
  const effectiveTerms = terms.length > 0 ? terms : ['3', '12'];

  // 交叉组合 year × term → 学期列表
  for (const year of years) {
    for (const term of effectiveTerms) {
      const termNum = term === '3' ? 1 : 2;
      const yearStart = parseInt(year.split('-')[0]);
      const isFirst = termNum === 1;
      const s = new Semester();
      s.id = `${year}-${termNum}`;
      s.name = `${year} 第${isFirst ? '一' : '二'}学期`;
      s.startDate = new Date(isFirst ? `${yearStart}-09-10` : `${yearStart + 1}-02-28`);
      s.endDate = new Date(isFirst ? `${yearStart + 1}-01-20` : `${yearStart + 1}-07-10`);
      semesters.push(s);
    }
  }

  // 按 id 升序排列（旧→新）
  semesters.sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
  return semesters;
}

interface GradeItem {
  kcmc?: string;
  kch?: string;
  xf?: number | string;
  cj?: number | string;
  jd?: number | string;
  djjbmc?: string;
  xnm?: string;
  xqm?: string;
}

function parseGradesFromJson(json: string): Course[] {
  try {
    const data = JSON.parse(json) as GradesResponse;
    const items = data.items ?? data.rows ?? [];
    return items.map(item => {
      const c = new Course();
      c.uid = `course_${item.kch ?? ''}_${item.xnm ?? ''}_${item.xqm ?? ''}`;
      c.courseId = item.kch as string ?? '';
      c.name = item.kcmc as string ?? '';
      const rawCredits = parseFloat(String(item.xf ?? '0'));
      c.credits = isNaN(rawCredits) ? 0 : rawCredits;
      const rawGrade = parseFloat(String(item.cj ?? '-1'));
      c.grade = isNaN(rawGrade) ? -1 : rawGrade;
      const rawGradePoint = parseFloat(String(item.jd ?? '-1'));
      c.gradePoint = isNaN(rawGradePoint) ? -1 : rawGradePoint;
      c.gradeLevel = item.djjbmc as string ?? '';
      c.semester = `${item.xnm ?? ''}-${item.xqm ?? ''}`;
      return c;
    });
  } catch {
    return [];
  }
}

interface CourseScheduleItem {
  xqj?: string;    // 星期几 (1-7)
  dsz?: string;    // 单双周 ('0'=单周, '1'=双周, '2'=均有)
  kcb?: string;    // 课程信息 HTML: "课程名<br>课程号<br>教师<br>地点zwf..."
  xxq?: string;    // 学期半段 (含 "秋"/"冬"/"春"/"夏")
  djj?: string;    // 开始节次
  skcd?: string;   // 上课节数（时长）
  kch_id?: string; // 课程ID（备用）
  kcmc?: string;   // 课程名（备用）
  jxb_id?: string; // 教学班ID
}

interface CourseScheduleResponseWithId {
  kbList?: Array<Record<string, Object>>;
  xh?: string;    // 学号（响应中包含）
}

function parseCourseScheduleFromJson(json: string, semesterId: string): Course[] {
  try {
    const data = JSON.parse(json) as CourseScheduleResponseWithId;

    // 提取学号（如果尚未设置）
    if (data.xh && (data.xh as string).length > 0 && savedStudentId.length === 0) {
      savedStudentId = data.xh as string;
      console.info(`[Timetable] Extracted student ID from response: ${savedStudentId}`);
    }

    const kbList = data.kbList ?? [];
    const courseMap = new Map<string, Course>();

    for (const rawItem of kbList) {
      const item = rawItem as CourseScheduleItem;

      // 从 kcb HTML 中解析课程名、教师、地点
      // 格式: "课程名<br>课程号<br>教师<br>地点zwf..."
      const kcbHtml = item.kcb as string ?? '';
      let courseName = item.kcmc as string ?? '';
      let teacher = '';
      let location = '';

      if (kcbHtml.length > 0) {
        const match = kcbHtml.match(/(.*?)<br>(.*?)<br>(.*?)<br>(.*?)zwf/);
        if (match) {
          // 将半角括号替换为全角（与 Flutter 实现一致）
          courseName = match[1].replace(/\(/g, '（').replace(/\)/g, '）');
          teacher = match[3];
          location = match[4] ?? '';
        } else {
          // fallback: 尝试只取第一个 <br> 前的内容作为课程名
          const simpleMatch = kcbHtml.match(/^(.*?)<br>/);
          if (simpleMatch) {
            courseName = simpleMatch[1].replace(/\(/g, '（').replace(/\)/g, '）');
          }
        }
      }

      if (courseName.length === 0) {
        continue;
      }

      // 获取或创建 Course
      const courseKey = item.kch_id as string ?? courseName;
      if (!courseMap.has(courseKey)) {
        const c = new Course();
        c.uid = `course_${courseKey}_${semesterId}`;
        c.courseId = item.kch_id as string ?? '';
        c.name = courseName;
        c.teacher = teacher;
        c.credits = 0;
        c.semester = semesterId;
        courseMap.set(courseKey, c);
      } else {
        // 如果教师信息已解析，更新（首次可能为空）
        const existing = courseMap.get(courseKey)!;
        if (existing.teacher.length === 0 && teacher.length > 0) {
          existing.teacher = teacher;
        }
      }

      // 解析上课时间
      const weekDay = parseInt(item.xqj as string ?? '1');
      const startPeriod = parseInt(item.djj as string ?? '1');
      const duration = parseInt(item.skcd as string ?? '2');
      const endPeriod = startPeriod + duration - 1;

      // 解析单双周：'0'=单周, '1'=双周, '2'(或其他)=均有
      const dsz = item.dsz as string ?? '2';
      const oddWeek = dsz !== '1';
      const evenWeek = dsz !== '0';
      const weeks: number[] = [];
      for (let w = 1; w <= 20; w++) {
        if ((oddWeek && w % 2 === 1) || (evenWeek && w % 2 === 0)) {
          weeks.push(w);
        }
      }

      // 解析学期半段（秋/春=前半, 冬/夏=后半）
      const xxq = item.xxq as string ?? '';
      const isFirstHalf = xxq.includes('秋') || xxq.includes('春');

      const courseSlot = new CourseTimeSlot(weekDay, startPeriod, endPeriod, location, weeks, isFirstHalf);
      courseMap.get(courseKey)!.timeSlots.push(courseSlot);
    }
    return Array.from(courseMap.values());
  } catch {
    return [];
  }
}

interface ExamItem {
  kcmc?: string;   // 课程名称
  kch?: string;    // 课程号
  kssj?: string;   // 考试开始时间
  jssj?: string;   // 考试结束时间
  jsmc?: string;   // 考场（地点）
  zwxh?: string;   // 座位号
  xnm?: string;    // 学年
  xqm?: string;    // 学期
}

function parseExamsFromJson(json: string, semesterId: string): Exam[] {
  try {
    const data = JSON.parse(json) as ExamsResponse;
    const items = data.items ?? data.rows ?? [];
    return items.map(rawItem => {
      const item = rawItem as ExamItem;
      const e = new Exam();
      e.uid = `exam_${item.kch ?? ''}_${semesterId}`;
      e.courseName = item.kcmc as string ?? '';
      e.startTime = new Date(item.kssj as string ?? '');
      e.endTime = new Date(item.jssj as string ?? '');
      e.location = item.jsmc as string ?? '';
      e.seatNo = item.zwxh as string ?? '';
      e.semester = semesterId;
      e.type = e.courseName.includes('期中') ? 'midterm' : 'final';
      return e;
    });
  } catch {
    return [];
  }
}

interface TodoItem {
  kcmc?: string;
  bzmc?: string;
  jzsj?: string;
}

function parseTodosFromJson(json: string, semesterId: string): Todo[] {
  try {
    const data = JSON.parse(json) as TodosResponse;
    const items = data.items ?? [];
    return items.map((item, idx) => {
      const t = new Todo();
      t.uid = `todo_${semesterId}_${idx}`;
      t.courseName = item.kcmc as string ?? '';
      t.title = item.bzmc as string ?? '';
      t.dueTime = new Date(item.jzsj as string ?? '');
      t.semester = semesterId;
      return t;
    });
  } catch {
    return [];
  }
}
