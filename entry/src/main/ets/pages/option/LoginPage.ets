// LoginPage.ets - 统一身份认证登录页（Modal 底部弹出）

import { AppKeys } from '../Index';
import { StorageService } from '../../service/StorageService';
import { login, getSsoLoginUrl, setCookies, BASE_JW, fetchStudentInfo, setStudentId, getStudentId, extractTicketFromCookies, setCachedStudentInfo } from '../../service/NetworkService';
import http from '@ohos.net.http';
import common from '@ohos.app.ability.common';
import { webview } from '@kit.ArkWeb';
import { BusinessError } from '@kit.BasicServicesKit';

interface GeneratedTypeLiteralInterface_8 {
  getErrorCode(): number;
  getErrorInfo(): string;
}
interface GeneratedTypeLiteralInterface_7 {
  error: GeneratedTypeLiteralInterface_8;
}
interface GeneratedTypeLiteralInterface_6 {
  url: string;
}
interface GeneratedTypeLiteralInterface_5 {
  url: string;
}
@Component
export struct LoginPage {
  @StorageLink(AppKeys.USERNAME) username: string = '';
  @StorageLink(AppKeys.IS_LOGGED_IN) isLoggedIn: boolean = false;
  @StorageLink(AppKeys.IS_GRS) isGrs: boolean = false;
  @State studentId: string = '';
  @State password: string = '';
  @State isLoading: boolean = false;
  @State showPassword: boolean = false;
  @State showWebLogin: boolean = false;
  @State webLoginUrl: string = '';
  @State webLoginMessage: string = '';
  private pathStack: NavPathStack | null = null;
  private storageService: StorageService | null = null;
  private webviewController: webview.WebviewController = new webview.WebviewController();
  private webCheckTimer: number = -1;
  private webLoginHandled: boolean = false;

  aboutToAppear(): void {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.storageService = new StorageService(context);
    } catch {}
  }

  private async doLogin(): Promise<void> {
    if (this.studentId.trim().length === 0 || this.password.trim().length === 0) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: '请填写学号和密码' });
      } catch {}
      return;
    }

    this.isLoading = true;

    const result = await login(this.studentId.trim(), this.password);

    if (result.success) {
      // 保存学号
      setStudentId(this.studentId.trim());
      this.onLoginSuccess(result.cookies, result.isGrs);
    } else {
      const message = result.message;
      try {
        this.getUIContext().getPromptAction().showDialog({
          title: '登录失败',
          message: message,
          buttons: [
            { text: '确定', color: '#000000' }
          ]
        }).catch(() => {
          // TODO: Implement error handling.
        });
      } catch {}
    }

    this.isLoading = false;
  }

  private async onLoginSuccess(cookies: string, isGrs: boolean): Promise<void> {
    if (this.webCheckTimer !== -1) {
      clearInterval(this.webCheckTimer);
      this.webCheckTimer = -1;
    }

    // 保存 cookies
    setCookies(cookies);
    this.storageService?.saveString('cookies', cookies);

    // 获取真实学号
    // 优先使用登录时输入的学号（账号密码登录）或已保存的学号
    let username = this.studentId.trim();
    let finalIsGrs = isGrs;

    // 无论哪种登录方式，都在后台异步获取完整学生信息（不阻塞登录流程）
    console.info('[Login] Fetching student info in background...');
    fetchStudentInfo().then((info) => {
      if (info.success) {
        if (info.name.length > 0) {
          console.info(`[Login] Got student name: ${info.name}`);
        }
        // 缓存学生信息
        setCachedStudentInfo(info);
        const infoStr = JSON.stringify(info);
        AppStorage.set(AppKeys.STUDENT_INFO, infoStr);
        this.storageService?.saveString('student_info', infoStr);
      }
    }).catch((e: Error) => {
      console.warn(`[Login] fetchStudentInfo failed: ${e.message}`);
    });

    // 如果 API 没有返回学号，回退到已保存的
    if (username.length === 0) {
      const saved = getStudentId();
      if (saved.length > 0) {
        username = saved;
        console.info(`[Login] Using savedStudentId: ${username}`);
      } else {
        username = 'web_user';
        console.warn('[Login] Could not get student ID, using web_user');
      }
    }

    // 保存学号到 NetworkService（若尚未设置）
    if (username !== 'web_user') {
      setStudentId(username);
    }

    // 设置所有状态
    AppStorage.set(AppKeys.USERNAME, username);
    AppStorage.set(AppKeys.IS_LOGGED_IN, true);
    AppStorage.set(AppKeys.IS_GRS, finalIsGrs);
    this.storageService?.saveUsername(username);
    this.storageService?.saveIsGrs(finalIsGrs);

    console.info(`[Login] Login success, username: ${username}, isGrs: ${finalIsGrs}`);

    try {
      this.getUIContext().getPromptAction().showToast({ message: '登录成功' });
    } catch {}

    // 关闭登录页面
    this.pathStack?.pop(true);
  }

  private openWebLogin(): void {
    this.webLoginUrl = getSsoLoginUrl();
    // 每次打开都新建 WebviewController，避免复用旧状态导致白屏
    this.webviewController = new webview.WebviewController();
    this.showWebLogin = true;
    this.webLoginMessage = '正在加载登录页面...';
    this.webLoginHandled = false;

    // 启动定时器检查 URL（每 1.5 秒一次）
    this.webCheckTimer = setInterval(() => {
      try {
        const url = this.webviewController.getUrl();
        if (url && url.length > 0) {
          console.info(`[WebLogin] Current URL: ${url}`);
          // 登录成功后 CAS 会重定向到教务系统（不含 cas/login 且含 jwglxt 或 zdbk）
          if ((url.includes('jwglxt') || url.includes('zdbk.zju.edu.cn')) &&
              !url.includes('cas/login') && !url.includes('zjuam')) {
            console.info(`[WebLogin] Detected successful login, URL: ${url}`);
            this.fetchWebCookies();
          }
        }
      } catch (error) {
        // Ignore errors during URL check
      }
    }, 1500);
  }

  private closeWebLogin(): void {
    this.showWebLogin = false;
    if (this.webCheckTimer !== -1) {
      clearInterval(this.webCheckTimer);
      this.webCheckTimer = -1;
    }
  }

  private cleanWebCookies(raw: string): string {
    const parts: string[] = [];
    const attrs = new Set(['path', 'domain', 'expires', 'max-age', 'samesite', 'secure', 'httponly']);
    for (const line of raw.split(/[;\n]/)) {
      const segment = line.trim();
      if (segment.length === 0) continue;
      const eqIdx = segment.indexOf('=');
      if (eqIdx > 0) {
        const name = segment.substring(0, eqIdx).trim();
        const val = segment.substring(eqIdx + 1).trim();
        if (name.length > 0 && !attrs.has(name.toLowerCase())) {
          parts.push(`${name}=${val}`);
        }
      }
    }
    return parts.join('; ');
  }

  private async exchangeCasForJwSession(iplanet: string): Promise<string | null> {
    try {
      const serviceUrl = `${BASE_JW}/xtgl/login_ssologin.html`;
      const casServiceUrl = `https://zjuam.zju.edu.cn/cas/login?service=${encodeURIComponent(serviceUrl)}`;
      const request = http.createHttp();
      const response = await request.request(casServiceUrl, {
        method: http.RequestMethod.GET,
        header: {
          'Cookie': `iPlanetDirectoryPro=${iplanet}`,
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        },
        connectTimeout: 15000,
        readTimeout: 15000
      });
      request.destroy();
      const cookies = response.cookies as string ?? '';
      const jsessionid = this.extractCookieValue(cookies, 'JSESSIONID');
      const route = this.extractCookieValue(cookies, 'route');
      if (jsessionid.length > 0) {
        return route.length > 0 ? `JSESSIONID=${jsessionid}; route=${route}` : `JSESSIONID=${jsessionid}`;
      }
      return null;
    } catch (err) {
      console.error(`[exchangeCasForJwSession] Failed: ${(err as Error).message}`);
      return null;
    }
  }

  private extractCookieValue(cookieStr: string, name: string): string {
    const parts = cookieStr.split(/[,\n]/);
    for (const part of parts) {
      const segment = part.trim().split(';')[0].trim();
      if (segment.startsWith(`${name}=`)) {
        return segment.substring(`${name}=`.length);
      }
    }
    return '';
  }

  private async fetchWebCookies(): Promise<void> {
    // 防止重复处理（onPageEnd 和定时器可能同时触发）
    if (this.webLoginHandled) {
      return;
    }
    this.webLoginHandled = true;

    try {
      // 停止定时器
      if (this.webCheckTimer !== -1) {
        clearInterval(this.webCheckTimer);
        this.webCheckTimer = -1;
      }

      console.info('[WebLogin] Fetching cookies after successful login...');

      // 获取当前 WebView 的 URL
      const currentUrl = this.webviewController.getUrl();
      console.info(`[WebLogin] Current WebView URL: ${currentUrl}`);

      // 尝试从 URL 中提取学号
      if (currentUrl && currentUrl.length > 0) {
        const usercodeMatch = currentUrl.match(/[?&](?:usercode|xh|username)=([^&]+)/);
        if (usercodeMatch) {
          this.studentId = decodeURIComponent(usercodeMatch[1]);
          console.info(`[WebLogin] Extracted student ID from URL: ${this.studentId}`);
        }
      }

      // 优先尝试直接获取教务系统的会话 cookie（JSESSIONID / route）
      // WebView 里 HttpOnly 的 iPlanetDirectoryPro 通常读不到，但 JW 会话 cookie 可能可读
      const jwUrls: string[] = [currentUrl ?? '', `${BASE_JW}/jwglxt`, BASE_JW, 'https://zdbk.zju.edu.cn/jwglxt'];
      let jwCookieStr = '';
      for (const url of jwUrls) {
        if (!url || url.length === 0) continue;
        try {
          const c = webview.WebCookieManager.fetchCookieSync(url, false);
          if (c && c.length > 0 && (c.includes('JSESSIONID') || c.includes('route'))) {
            console.info(`[WebLogin] Fetched JW cookies from ${url}, length: ${c.length}`);
            jwCookieStr = c;
            break;
          }
        } catch (e) {
          console.warn(`[WebLogin] Failed to fetch JW cookies for ${url}: ${(e as Error).message}`);
        }
      }

      if (jwCookieStr.length > 0) {
        const cleanCookies = this.cleanWebCookies(jwCookieStr);
        console.info(`[WebLogin] Using JW cookies directly: ${cleanCookies.substring(0, 120)}`);
        this.onLoginSuccess(cleanCookies, false);
        this.showWebLogin = false;
        return;
      }

      // 兜底：尝试读取 CAS 的 iPlanetDirectoryPro（通常因 HttpOnly 而失败）
      const casUrls: string[] = ['https://zjuam.zju.edu.cn/cas', currentUrl ?? '', `${BASE_JW}/jwglxt`];
      let cookieStr = '';
      for (const url of casUrls) {
        if (!url || url.length === 0) continue;
        try {
          const c = webview.WebCookieManager.fetchCookieSync(url, false);
          if (c && c.includes('iPlanetDirectoryPro')) {
            console.info(`[WebLogin] Fetched CAS cookies from ${url}, length: ${c.length}`);
            cookieStr = c;
            break;
          }
        } catch (e) {
          console.warn(`[WebLogin] Failed to fetch CAS cookies for ${url}: ${(e as Error).message}`);
        }
      }

      const iplanet = extractTicketFromCookies(cookieStr);
      console.info(`[WebLogin] iPlanetDirectoryPro length: ${iplanet.length}`);

      if (iplanet.length === 0) {
        console.warn('[WebLogin] Missing both JW cookies and iPlanetDirectoryPro');
        this.webLoginMessage = '未检测到登录状态，请检查是否已正确登录';
        this.webLoginHandled = false;
        return;
      }

      // 使用 iPlanetDirectoryPro 换取 JW 系统会话
      this.webLoginMessage = '正在获取教务系统会话...';
      const jwCookies: string | null = await this.exchangeCasForJwSession(iplanet);
      if (!jwCookies || jwCookies.length === 0) {
        console.warn('[WebLogin] Failed to exchange CAS ticket for JW session');
        this.webLoginMessage = '获取教务系统会话失败，请重试';
        this.webLoginHandled = false;
        return;
      }

      console.info(`[WebLogin] JW cookies obtained via exchange, length: ${jwCookies.length}`);
      this.onLoginSuccess(jwCookies, false);
      this.showWebLogin = false;
    } catch (error) {
      const err = error as BusinessError;
      console.error(`[WebLogin] Fetch cookies failed: code=${err.code}, message=${err.message}`);
      this.webLoginMessage = '获取登录状态失败，请重试';
      this.webLoginHandled = false;
    }
  }

  build() {
    NavDestination() {
      Column() {
        // 拖拽指示条
        Row()
          .width(40).height(4)
          .borderRadius(2)
          .backgroundColor($r('app.color.separator'))
          .margin({ top: 12, bottom: 16 })

        // ── 登录方式切换 ──
        Row({ space: 4 }) {
          Button({ type: ButtonType.Normal }) {
            Text('学号密码')
              .fontSize(14)
              .fontColor(!this.showWebLogin ? Color.White : $r('app.color.text_secondary'))
              .fontWeight(FontWeight.Medium)
          }
          .width('50%')
          .height(36)
          .borderRadius(8)
          .backgroundColor(!this.showWebLogin ? $r('app.color.color_blue') : $r('app.color.progress_bg'))
          .onClick(() => { this.closeWebLogin(); })

          Button({ type: ButtonType.Normal }) {
            Text('网页认证')
              .fontSize(14)
              .fontColor(this.showWebLogin ? Color.White : $r('app.color.text_secondary'))
              .fontWeight(FontWeight.Medium)
          }
          .width('50%')
          .height(36)
          .borderRadius(8)
          .backgroundColor(this.showWebLogin ? $r('app.color.color_blue') : $r('app.color.progress_bg'))
          .onClick(() => { this.openWebLogin(); })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 20 })

        if (!this.showWebLogin) {
          // 学号密码登录表单
          Column({ space: 0 }) {
            Row({ space: 12 }) {
              Text('学号')
                .fontSize(15).fontColor($r('app.color.text_secondary')).width(48)
              TextInput({ text: this.studentId, placeholder: '请输入学号' })
                .fontSize(16).fontColor($r('app.color.text_primary'))
                .placeholderColor($r('app.color.text_tertiary'))
                .backgroundColor(Color.Transparent).border({ width: 0 })
                .type(InputType.Number).layoutWeight(1)
                .onChange((text: string) => { this.studentId = text; })
            }
            .padding({ left: 16, right: 16, top: 14, bottom: 14 })

            Divider().strokeWidth(0.5).color($r('app.color.separator')).margin({ left: 76 })

            Row({ space: 12 }) {
              Text('密码')
                .fontSize(15).fontColor($r('app.color.text_secondary')).width(48)
              TextInput({ text: this.password, placeholder: '请输入密码' })
                .fontSize(16).fontColor($r('app.color.text_primary'))
                .placeholderColor($r('app.color.text_tertiary'))
                .backgroundColor(Color.Transparent).border({ width: 0 })
                .type(this.showPassword ? InputType.Normal : InputType.Password)
                .layoutWeight(1)
                .onChange((text: string) => { this.password = text; })

              Button({ type: ButtonType.Normal }) {
                Text(this.showPassword ? '🙈' : '👁️').fontSize(18)
              }
              .backgroundColor(Color.Transparent)
              .onClick(() => { this.showPassword = !this.showPassword; })
            }
            .padding({ left: 16, right: 16, top: 14, bottom: 14 })
          }
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(16)
          .margin({ left: 16, right: 16 })

          // 提示
          Text('登录即代表您同意我们的服务条款。本应用不会在设备外存储您的明文密码。')
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
            .textAlign(TextAlign.Center)
            .padding({ left: 32, right: 32, top: 16, bottom: 24 })

          // 登录按钮
          Button({ stateEffect: true }) {
            if (this.isLoading) {
              LoadingProgress()
                .width(24).height(24).color(Color.White)
            } else {
              Text('登录')
                .fontSize(16).fontColor(Color.White).fontWeight(FontWeight.Medium)
            }
          }
          .width('100%')
          .height(52)
          .borderRadius(16)
          .backgroundColor($r('app.color.color_blue'))
          .margin({ left: 16, right: 16 })
          .enabled(!this.isLoading)
          .onClick(() => this.doLogin())
        } else {
          // 网页认证视图
          Column({ space: 8 }) {
            if (this.webLoginMessage.length > 0) {
              Text(this.webLoginMessage)
                .fontSize(13)
                .fontColor($r('app.color.color_blue'))
                .textAlign(TextAlign.Center)
                .padding({ left: 16, right: 16, top: 4, bottom: 4 })
            }

            Web({ src: this.webLoginUrl, controller: this.webviewController })
              .javaScriptAccess(true)
              .domStorageAccess(true)
              .fileAccess(true)
              .databaseAccess(true)
              .mixedMode(MixedMode.All)
              .onControllerAttached(() => {
                try {
                  const currentUrl = this.webviewController.getUrl();
                  if (!currentUrl || currentUrl.length === 0 || currentUrl === 'about:blank') {
                    console.info(`[WebLogin] Controller attached, loading: ${this.webLoginUrl}`);
                    this.webviewController.loadUrl(this.webLoginUrl);
                  }
                } catch (e) {
                  console.error(`[WebLogin] loadUrl in onControllerAttached failed: ${(e as Error).message}`);
                }
              })
              .onPageBegin((event: GeneratedTypeLiteralInterface_5) => {
                if (event) {
                  console.info(`[WebLogin] Page begin: ${event.url}`);
                  this.webLoginMessage = '正在加载...';
                }
              })
              .onPageEnd((event: GeneratedTypeLiteralInterface_6) => {
                if (event) {
                  console.info(`[WebLogin] Page end: ${event.url}`);
                  this.webLoginMessage = '';
                  const url = event.url;
                  if (url && (url.includes('jwglxt') || url.includes('zdbk.zju.edu.cn')) &&
                      !url.includes('cas/login') && !url.includes('zjuam')) {
                    console.info(`[WebLogin] Detected successful login on page end: ${url}`);
                    this.fetchWebCookies();
                  }
                }
              })
              .onErrorReceive((event: GeneratedTypeLiteralInterface_7) => {
                if (event) {
                  const code = event.error.getErrorCode();
                  const info = event.error.getErrorInfo();
                  console.error(`[WebLogin] Error code=${code}, info=${info}`);
                  if (code !== -1) {
                    this.webLoginMessage = `加载失败 (${code})，请检查网络`;
                  }
                }
              })
              .width('100%')
              .layoutWeight(1)

            Text('在网页完成登录后，将自动保存登录状态')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .textAlign(TextAlign.Center)
              .padding({ left: 16, right: 16, top: 4, bottom: 8 })
          }
          .width('100%')
          .layoutWeight(1)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(16)
          .margin({ left: 16, right: 16 })
        }

        Blank().height(40)
      }
      .width('100%').height('100%')
      .backgroundColor($r('app.color.card_background'))
      .alignItems(HorizontalAlign.Center)
    }
    .hideTitleBar(true)
    .mode(NavDestinationMode.DIALOG)
    .onReady((ctx: NavDestinationContext) => { this.pathStack = ctx.pathStack; })
  }
}
