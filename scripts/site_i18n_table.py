"""官网首页的翻译表：中文原文 → (英文, 西班牙语)。scripts/site-i18n.py 用。
键要和 site/index.html 里的文字一模一样（可以带 <b>、<br> 这些小标签）。改了首页文字，这里跟着改。"""

T = {
    # <head>
    "夏夏账本 · 看一眼就知道钱去哪了": ("Xiaxia Ledger · See where your money went at a glance", "Xiaxia Ledger · Mira de un vistazo adónde se fue tu dinero"),
    "夏夏账本更新": ("Xiaxia Ledger updates", "Novedades de Xiaxia Ledger"),
    "主导航": ("Main navigation", "Navegación principal"),
    # 导航
    "看看界面": ("Tour", "Recorrido"),
    "连上 AI": ("Connect your AI", "Conecta tu IA"),
    "怎么装": ("Install", "Instalar"),
    "更新日志": ("Changelog", "Novedades"),
    "下载": ("Download", "Descargar"),
    # 头图
    "看一眼，<br><span class=\"nw\">就知道<em>钱去哪了</em>。</span>": ("One look,<br>and you know <em>where the money went</em>.", "Un vistazo,<br>y sabes <em>adónde se fue el dinero</em>."),
    "下载 Mac 版": ("Download for Mac", "Descargar para Mac"),
    "先看看界面": ("Take the tour first", "Ver el recorrido"),
    "免费下载": ("Free download", "Descarga gratuita"),
    "· 需要 macOS 14 Sonoma 或更新": ("· Requires macOS 14 Sonoma or later", "· Requiere macOS 14 Sonoma o posterior"),
    "夏夏：蓝头发的鲸鱼娘，在挥手打招呼": ("Xiaxia: a blue-haired whale girl waving hello", "Xiaxia: una chica ballena de pelo azul que saluda"),
    # 为什么
    "为什么用夏夏账本": ("Why Xiaxia Ledger", "Por qué Xiaxia Ledger"),
    "记账不累，看账不烦。": ("Logging isn't a chore. Reading isn't a headache.", "Apuntar no cansa. Mirar no agobia."),
    "它最擅长的是「看」：打开就知道这个月过得怎么样。记账这件事，交给你已经在用的 AI。": (
        "What it does best is show you: open it and you know how this month is going. Leave the logging to the AI you already use.",
        "Lo que mejor hace es enseñarte: la abres y sabes cómo va el mes. Deja el apuntar a la IA que ya usas."),
    "一屏看清": ("Everything on one screen", "Todo en una pantalla"),
    "这个月还剩多少、花钱快不快、钱花在哪、家底涨了没，每页一个重点，不用上下翻。": (
        "How much is left this month, how fast you're spending, where it goes, whether your net worth grew. One point per page, no scrolling.",
        "Cuánto queda este mes, a qué ritmo gastas, en qué se va, si tu patrimonio ha crecido. Una idea por página, sin desplazarte."),
    "说一句就记上": ("Say it and it's logged", "Lo dices y queda apuntado"),
    "夏夏给你出主意": ("Xiaxia gives you advice", "Xiaxia te aconseja"),
    "多出来的钱放哪、哪个订阅悄悄涨价了、谁的钱该催了，夏夏看着你的账本提醒你。": (
        "Where to put spare money, which subscription quietly got pricier, who still owes you: Xiaxia watches your ledger and reminds you.",
        "Dónde poner el dinero que sobra, qué suscripción ha subido sin avisar, quién te debe: Xiaxia mira tu libro y te lo recuerda."),
    "账本在你自己手里": ("Your ledger stays yours", "Tu libro es tuyo"),
    # 看看界面
    "选择页面": ("Choose a page", "Elige una página"),
    "总览：这个月还剩多少、花钱速度和上个月比快还是慢，夏夏的点评可以左右滑着看。": (
        "Overview: how much is left this month, whether you're spending faster or slower than last month, and Xiaxia's comments to swipe through.",
        "Resumen: cuánto queda este mes, si gastas más rápido o más lento que el mes pasado, y los comentarios de Xiaxia para deslizar."),
    "花销：这个月和上个月并排对比，圆饼、柱状随你切；夏夏告诉你哪类花多了、主要花在哪、怎么省。": (
        "Spending: this month next to last month, as a pie or bars; Xiaxia tells you which category grew, where most of it went and how to save.",
        "Gastos: este mes junto al anterior, en tarta o en barras; Xiaxia te dice qué categoría ha subido, en qué se fue más y cómo ahorrar."),
    "趋势：每个月存下多少，一眼看出是越过越好还是越差；连着几个月悄悄变多的开销会被揪出来。": (
        "Trends: how much you saved each month, so you can see if things are getting better or worse; costs that creep up month after month get called out.",
        "Tendencias: cuánto ahorraste cada mes, para ver si vas a mejor o a peor; los gastos que suben poco a poco salen a la luz."),
    "家底：真正属于你的有多少，钱分别在哪：能随时用的、存着的、店里的、欠着的。": (
        "Net worth: how much is really yours and where it sits: free to spend, saved, in the shop, or owed.",
        "Patrimonio: cuánto es realmente tuyo y dónde está: disponible, ahorrado, en la tienda o debido."),
    "欠款与分期：我欠谁、谁欠我、分期还剩几期，夏夏帮你排还钱计划，也会俏皮地帮你催款。": (
        "Debts & instalments: who you owe, who owes you, how many instalments remain; Xiaxia plans your repayments and nudges people who owe you.",
        "Deudas y plazos: a quién debes, quién te debe, cuántos plazos quedan; Xiaxia te organiza los pagos y da un toque a quien te debe."),
    "夏夏账本「总览」页截图（示例数据）": ("Screenshot of the Overview page in Xiaxia Ledger (sample data)", "Captura de la página Resumen de Xiaxia Ledger (datos de ejemplo)"),
    "总览": ("Overview", "Resumen"),
    "花销": ("Spending", "Gastos"),
    "趋势": ("Trends", "Tendencias"),
    "家底": ("Net worth", "Patrimonio"),
    "欠款与分期": ("Debts & instalments", "Deudas y plazos"),
    "还有存钱目标、订阅、流水和改动记录。顶上的月份点一下就能选年选月。支持多个账本（比如「个人」和「我的小店」）和多种货币。": (
        "There are also savings goals, subscriptions, transactions and a change history. Click the month at the top to pick any month or year. Several ledgers (say “Personal” and “My shop”) and several currencies are supported.",
        "También hay objetivos de ahorro, suscripciones, movimientos e historial de cambios. Pulsa el mes de arriba para elegir mes y año. Admite varios libros (por ejemplo «Personal» y «Mi tienda») y varias monedas."),
    # 连上 AI
    "你已经在用的 AI，<br>就是你的记账员。": ("The AI you already use<br>is your bookkeeper.", "La IA que ya usas<br>es tu contable."),
    "能自动连上的 AI 工具": ("AI tools that connect automatically", "Herramientas de IA que se conectan solas"),
    "Claude 桌面版": ("Claude Desktop", "Claude Desktop"),
    "别的 AI 也行：在设置里点「一键复制配置提示词」，粘给它，它会自己接好。用 DeepSeek、通义千问、Kimi 的，可以通过 Hermes Agent 或 Cherry Studio 连。": (
        "Other AIs work too: in Settings, copy the setup prompt, paste it to your AI and it wires itself up. If you use DeepSeek, Qwen or Kimi, connect through Hermes Agent or Cherry Studio.",
        "Otras IA también valen: en Ajustes, copia el texto de configuración, pégaselo a tu IA y se conecta sola. Si usas DeepSeek, Qwen o Kimi, conéctalas con Hermes Agent o Cherry Studio."),
    "示例对话：用户说午饭花了 12,50，AI 回复已记进账本并告诉本月餐饮总额": (
        "Sample chat: the user says lunch cost 12,50; the AI replies that it is logged and gives this month's food total",
        "Conversación de ejemplo: el usuario dice que la comida costó 12,50; la IA responde que está apuntado y da el total de comida del mes"),
    "中午和同事吃拉面 12,50，信用卡付的": ("Ramen with a colleague at lunch, 12,50, paid by credit card", "Ramen con un compañero al mediodía, 12,50, con tarjeta de crédito"),
    "Claude · 已连上夏夏账本": ("Claude · connected to Xiaxia Ledger", "Claude · conectado a Xiaxia Ledger"),
    "记好了：<b>餐饮 −12,50 €</b>（信用卡，今天）。这个月吃饭一共 186,40 €，比上月同期少 23 €，继续保持～": (
        "Logged: <b>Food −12,50 €</b> (credit card, today). Food this month comes to 186,40 €, 23 € less than this time last month. Keep it up!",
        "Apuntado: <b>Comida −12,50 €</b> (tarjeta de crédito, hoy). En comida llevas 186,40 € este mes, 23 € menos que a estas alturas del mes pasado. ¡Sigue así!"),
    "这个月还能花多少？": ("How much can I still spend this month?", "¿Cuánto puedo gastar todavía este mes?"),
    "按你的存钱目标，到月底还能花 <b>813,56 €</b>，平均每天 116 €。房租已经扣过了，放心。": (
        "With your savings goal, you can spend <b>813,56 €</b> until the end of the month, about 116 € a day. Rent is already paid, so relax.",
        "Con tu objetivo de ahorro, puedes gastar <b>813,56 €</b> hasta fin de mes, unos 116 € al día. El alquiler ya está pagado, tranquilo."),
    # 角色
    "认识一下": ("Say hello", "Te presento a"),
    "夏夏和 AI 伙伴们": ("Xiaxia and the AI companions", "Xiaxia y sus compañeros de IA"),
    "账本里的小角色会眨眼、会说话。你连的是哪个 AI，就由哪个伙伴来陪你。女生版、男生版各一套，在 app 设置里随时切换。": (
        "The little characters in the app blink and talk. Whichever AI you connect, its companion keeps you company. There is a girl set and a boy set; switch any time in Settings.",
        "Los personajes de la app parpadean y hablan. Según la IA que conectes, te acompaña su compañero. Hay un juego de chicas y otro de chicos; cámbialo cuando quieras en Ajustes."),
    "选择角色造型": ("Choose the character set", "Elige el estilo de los personajes"),
    "女生版": ("Girls", "Chicas"),
    "男生版": ("Boys", "Chicos"),
    "主角": ("Lead", "Protagonista"),
    "抱着小算盘的鲸鱼娘，帮你看账、给你出主意，偶尔毒舌一下。": (
        "A whale girl hugging a little abacus. She reads your books, gives advice and is a bit cheeky now and then.",
        "Una chica ballena con su pequeño ábaco. Mira tus cuentas, te aconseja y a veces es un poco descarada."),
    "抱着小算盘的鲸鱼少年，帮你看账、给你出主意，偶尔毒舌一下。": (
        "A whale boy hugging a little abacus. He reads your books, gives advice and is a bit cheeky now and then.",
        "Un chico ballena con su pequeño ábaco. Mira tus cuentas, te aconseja y a veces es un poco descarado."),
    "Claude 的伙伴": ("Claude's companion", "Compañero de Claude"),
    "温柔细心，帮你记账、整理分类。": ("Gentle and careful: logs for you and tidies your categories.", "Amable y cuidadoso: apunta por ti y ordena tus categorías."),
    "Codex 的伙伴": ("Codex's companion", "Compañero de Codex"),
    "动作麻利，导入对账单、对账都交给这位。": ("Quick on the job: importing statements and reconciling go here.", "Rápido y eficaz: importar extractos y conciliar es cosa suya."),
    "Gemini 和其它 AI": ("Gemini and other AIs", "Gemini y otras IA"),
    "好奇心满满，什么 AI 来了都能接上。": ("Endlessly curious: gets along with whatever AI shows up.", "Lleno de curiosidad: se entiende con cualquier IA que llegue."),
    "夏夏账本": ("Xiaxia Ledger", "Xiaxia Ledger"),
    "夏夏": ("Xiaxia", "Xiaxia"),
    "小橘": ("Xiaoju", "Xiaoju"),
    "小紫": ("Xiaozi", "Xiaozi"),
    "小星": ("Xiaoxing", "Xiaoxing"),
    # iPhone
    "iPhone 版": ("iPhone", "iPhone"),
    "iPhone 总览页（示例数据）": ("iPhone Overview page (sample data)", "Página Resumen en iPhone (datos de ejemplo)"),
    # 怎么装
    "三步装好，一分钟。": ("Three steps, one minute.", "Tres pasos, un minuto."),
    "需要 macOS 14 Sonoma 或更新的系统。看系统版本：点屏幕左上角的苹果菜单 →「关于本机」。": (
        "Requires macOS 14 Sonoma or later. To check your version, open the Apple menu in the top-left corner → About This Mac.",
        "Requiere macOS 14 Sonoma o posterior. Para ver tu versión, abre el menú Apple en la esquina superior izquierda → Acerca de este Mac."),
    "下载并拖进「应用程序」": ("Download and drag to Applications", "Descarga y arrastra a Aplicaciones"),
    "点上面的下载按钮，打开下载好的 <span class=\"k\">xiaxia-ledger.dmg</span>，把「夏夏账本」图标拖到旁边的「应用程序」文件夹。": (
        "Click the download button above, open the downloaded <span class=\"k\">xiaxia-ledger.dmg</span>, and drag the 夏夏账本 icon onto the Applications folder next to it.",
        "Pulsa el botón de descarga de arriba, abre el <span class=\"k\">xiaxia-ledger.dmg</span> descargado y arrastra el icono 夏夏账本 a la carpeta Aplicaciones que aparece al lado."),
    "第一次打开": ("Open it the first time", "Ábrela por primera vez"),
    "在「应用程序」里双击「夏夏账本」。Mac 会问「这是从互联网下载的 app，确定要打开吗」，点<b>打开</b>。以后就和普通 app 一样了。": (
        "In Applications, double-click 夏夏账本. Your Mac asks whether to open an app downloaded from the internet; click <b>Open</b>. From then on it behaves like any other app.",
        "En Aplicaciones, haz doble clic en 夏夏账本. El Mac pregunta si quieres abrir una app descargada de internet; pulsa <b>Abrir</b>. A partir de ahí funciona como cualquier otra app."),
    "连上你的 AI": ("Connect your AI", "Conecta tu IA"),
    "打不开，提示「无法验证开发者」或「已损坏」怎么办？": ("It won't open and says the developer can't be verified, or that it's damaged. What now?", "No se abre y dice que no se puede verificar el desarrollador o que está dañada. ¿Qué hago?"),
    "先关掉那个提示框。": ("Close that dialog first.", "Primero cierra ese aviso."),
    "打开「系统设置」→「隐私与安全性」，拉到最下面。": ("Open System Settings → Privacy & Security and scroll to the bottom.", "Abre Ajustes del Sistema → Privacidad y seguridad y baja hasta el final."),
    "看到「已阻止使用\"夏夏账本\"」，点旁边的<b>仍要打开</b>，输入开机密码。": (
        "Where it says 夏夏账本 was blocked, click <b>Open Anyway</b> next to it and enter your Mac password.",
        "Donde dice que se ha bloqueado 夏夏账本, pulsa <b>Abrir igualmente</b> e introduce la contraseña del Mac."),
    "还是不行，就把 dmg 删掉重新下载一次（下载没完成也会这样）。": ("Still stuck? Delete the dmg and download it again (an incomplete download causes this too).", "¿Sigue sin ir? Borra el dmg y descárgalo otra vez (una descarga incompleta también lo provoca)."),
    "随时可以在 app 的「设置」→「AI 连接」里重新打开引导。也可以点「一键复制配置提示词」，粘给任何一个 AI，它会一步步帮你接好。": (
        "You can reopen the guide any time in the app under Settings → AI connections. Or copy the setup prompt and paste it to any AI; it will walk you through it.",
        "Puedes volver a abrir la guía cuando quieras en Ajustes → Conexiones de IA. O copia el texto de configuración y pégaselo a cualquier IA; te guiará paso a paso."),
    "我还没装任何 AI 工具。": ("I don't have any AI tool installed yet.", "Todavía no tengo ninguna herramienta de IA."),
    "推荐先装": ("We suggest starting with", "Te recomendamos empezar por"),
    "（有免费额度）。用 DeepSeek 的可以装 Hermes Agent；用通义千问、Kimi 的可以装 Cherry Studio。不连 AI 也能在 app 里手动「记一笔」。": (
        " (it has a free tier). DeepSeek users can install Hermes Agent; Qwen or Kimi users can install Cherry Studio. Without any AI you can still add entries by hand in the app.",
        " (tiene plan gratuito). Si usas DeepSeek, instala Hermes Agent; si usas Qwen o Kimi, Cherry Studio. Sin IA también puedes añadir apuntes a mano en la app."),
    "我的账本数据存在哪？安全吗？": ("Where is my ledger stored? Is it safe?", "¿Dónde se guarda mi libro? ¿Es seguro?"),
    "账本存在你自己的 Mac 上（开了 iCloud 云盘就跟着 iCloud 走），我们没有服务器，看不到你的账。注意：你让 AI 读账时，账目会发给你用的那个 AI 服务商，和你平时跟它聊天一样。夏夏账本不碰银行密码，对账单是你自己导出来交给它的。": (
        "The ledger lives on your own Mac (or in iCloud Drive if you use it). We run no server and cannot see your books. Note: when you let an AI read the ledger, those entries go to that AI provider, just like any chat with it. Xiaxia Ledger never touches bank passwords; statements are files you export and hand over yourself.",
        "El libro está en tu propio Mac (o en iCloud Drive si lo usas). No tenemos servidor y no vemos tus cuentas. Ojo: cuando dejas que una IA lea el libro, esos apuntes van al proveedor de esa IA, igual que cualquier conversación con ella. Xiaxia Ledger nunca toca contraseñas bancarias; los extractos los exportas y entregas tú."),
    "怎么更新？": ("How do I update?", "¿Cómo se actualiza?"),
    "有新版本时 app 会自己提醒你，点「安装更新」就行，账本不受影响。也可以回这个网页重新下载覆盖安装。": (
        "The app tells you when a new version is out; click Install Update and your ledger is untouched. You can also download it again here and install over the old one.",
        "La app te avisa cuando hay versión nueva; pulsa Instalar actualización y tu libro no se toca. También puedes descargarla de nuevo aquí e instalarla encima."),
    # 结尾
    "今天就开始，让夏夏帮你管钱。": ("Start today and let Xiaxia help with your money.", "Empieza hoy y deja que Xiaxia te ayude con tu dinero."),
    "下载、拖进「应用程序」、连上 AI，就这么简单。": ("Download, drag to Applications, connect your AI. That's it.", "Descarga, arrastra a Aplicaciones, conecta tu IA. Así de fácil."),
    "· macOS 14 Sonoma 或更新": ("· macOS 14 Sonoma or later", "· macOS 14 Sonoma o posterior"),
    "界面里的金额和人名都是示例数据。": ("Amounts and names in the screenshots are sample data.", "Los importes y nombres de las capturas son datos de ejemplo."),
    # 脚本里的文字
    "'夏夏账本「'+b.textContent+'」页截图（示例数据）'": ("'Xiaxia Ledger screenshot: '+b.textContent+' (sample data)'", "'Captura de Xiaxia Ledger: '+b.textContent+' (datos de ejemplo)'"),
    "'版本 '+ver": ("'Version '+ver", "'Versión '+ver"),
    "' · 免费'": ("' · Free'", "' · Gratis'"),
    "el.alt.replace(/（男生版）$/,'')+(look==='boy'?'（男生版）':'')": (
        "el.alt.replace(/ \\(boy version\\)$/,'')+(look==='boy'?' (boy version)':'')",
        "el.alt.replace(/ \\(versión chico\\)$/,'')+(look==='boy'?' (versión chico)':'')"),
    "// 记住选的语言（中文页靠它决定要不要跳去英文、西语页）": ("// remember the chosen language", "// remember the chosen language"),
    "// 截图切换": ("// tour tabs", "// tour tabs"),
    "// 女生版 / 男生版": ("// girls / boys", "// girls / boys"),
    "// 预载男生版，切换时不闪": ("// preload", "// preload"),
    "// 从自动更新文件读最新版本号和大小，读不到就保持「免费下载」": ("// version from appcast", "// version from appcast"),
    # 2026-11-25 官网改版新加、改过的
    "跳到正文": ("Skip to content", "Saltar al contenido"),
    "菜单": ("Menu", "Menú"),
    "<b>新</b>看看这次更新了什么 →": ("<b>New</b>See what's new →", "<b>Nuevo</b>Mira las novedades →"),
    "把网址发给自己": ("Send me the link", "Enviarme el enlace"),
    "'网址已复制，粘贴发给自己就行。'": ("'Link copied. Paste it into a message to yourself.'", "'Enlace copiado. Pégalo en un mensaje para ti.'"),
    "'复制不了，请长按地址栏复制：'": ("'Couldn’t copy. Long-press the address bar to copy: '", "'No se pudo copiar. Mantén pulsada la barra de direcciones para copiar: '"),
    "这个月还能剩 <b>813&nbsp;€</b>，比上月多哦 ✨": ("<b>813&nbsp;€</b> left this month, more than last ✨", "Este mes te sobran <b>813&nbsp;€</b>, más que el pasado ✨"),
    "第一次打开夏夏账本，它会找出你 Mac 上装了的 AI 工具，每个 AI 旁边点一下「连接」就行。连好以后，在 AI 里说话，账就记进夏夏账本；你在 app 里看。": (
        "The first time you open Xiaxia Ledger it finds the AI tools on your Mac; click Connect next to each one. After that, talk to your AI and it lands in the ledger; you look at it in the app.",
        "La primera vez que abres Xiaxia Ledger, busca las herramientas de IA de tu Mac; pulsa Conectar junto a cada una. Después, habla con tu IA y queda en el libro; tú lo miras en la app."),
    "连完夏夏账本自己测一遍，确认 AI 能读到账本。": (
        "After connecting, Xiaxia Ledger checks by itself that the AI can read your ledger.",
        "Tras conectar, Xiaxia Ledger comprueba por sí sola que la IA puede leer tu libro."),
    "第一次打开会弹出「连接你的 AI」，在你的 AI 旁边点<b>连接</b>，按提示重开一下 AI 工具，再对它说一句「记一笔：咖啡 3,20」试试。": (
        "On first launch a “Connect your AI” window appears. Click <b>Connect</b> next to your AI, restart the AI tool when asked, then try telling it “Log this: coffee 3,20”.",
        "Al abrirla por primera vez aparece «Conecta tu IA». Pulsa <b>Conectar</b> junto a tu IA, reiníciala cuando lo pida y prueba a decirle «Apunta: café 3,20»."),
    "没有弹出「连接你的 AI」，或者我想以后再连？": ("The “Connect your AI” window didn't appear, or I'd rather connect later.", "No ha salido «Conecta tu IA», o prefiero conectarla más tarde."),
    "「午饭 12,50」「把这张对账单导进来」，跟 Claude、Codex 等 AI 说就行，它帮你记、帮你分类。": (
        "“Lunch 12,50”, “import this bank statement”: just tell Claude, Codex or another AI, and it logs and categorises for you.",
        "«Comida 12,50», «importa este extracto»: díselo a Claude, Codex u otra IA y lo apunta y lo clasifica por ti."),
    "// 截图切换：点一下或用左右方向键": ("// tour tabs: click or arrow keys", "// tour tabs: click or arrow keys"),
    "// 手机上：把网址发给自己（能分享就弹分享，不能就复制）": ("// phone: send yourself the link", "// phone: send yourself the link"),
    "/* 配色从夏夏身上取：墨蓝头发、海水色发尾、金色算盘珠、奶油色围裙。橙色只给按钮。 */": ("/* palette from Xiaxia: ink-blue hair, sea-green tips, gold abacus beads, cream apron; orange only on buttons */", "/* palette from Xiaxia: ink-blue hair, sea-green tips, gold abacus beads, cream apron; orange only on buttons */"),
    "/* 四件事：像账本里的四行 */": ("/* four points, like ledger rows */", "/* four points, like ledger rows */"),
    "/* cast：拍立得 */": ("/* cast: polaroids */", "/* cast: polaroids */"),
    "/* 结尾 */": ("/* closing band */", "/* closing band */"),
    # 2026-11-25 iPhone 版
    "夏夏账本：Mac 上的原生记账 app，现在就能免费下载；iPhone 版即将推出，能随手记、拍小票，开了 iCloud 云盘还能和 Mac 同步同一本账。图表一眼看清收支、家底和欠款；记账直接跟你的 AI 说一句。": ("Xiaxia Ledger: a native money app for Mac, free to download now. The iPhone app is coming soon: quick entries, receipt photos, and with iCloud Drive turned on, the same ledger as your Mac. Charts show your income, spending, net worth and debts at a glance; to log something, just tell your AI.",
        "Xiaxia Ledger: una app nativa de finanzas para Mac, ya gratis para descargar. La app de iPhone llega muy pronto: apuntes rápidos, fotos de tiques y, con iCloud Drive activado, el mismo libro que en tu Mac. Los gráficos muestran de un vistazo ingresos, gastos, patrimonio y deudas; para apuntar algo, díselo a tu IA."),
    "看一眼就知道钱去哪了。Mac 版现在就能下载，iPhone 版即将推出；记账跟 AI 说一句就行。": ("See where your money went at a glance. Download for Mac now; the iPhone app is coming soon. To log something, just tell your AI.",
        "Mira de un vistazo adónde se fue tu dinero. Descárgala ya para Mac; la app de iPhone llega muy pronto. Para apuntar algo, díselo a tu IA."),
    "Mac 上的原生记账 app：图表一眼看清收支、家底和欠款，记账跟你的 AI 说一句就行。": (
        "A native money app for Mac. Charts show your income, spending, net worth and debts at a glance; to log something, just tell your AI.",
        "Una app nativa de finanzas para Mac. Los gráficos muestran de un vistazo ingresos, gastos, patrimonio y deudas; para apuntar algo, díselo a tu IA."),
    "iPhone 版即将推出 →": ("iPhone app coming soon →",
        "App de iPhone muy pronto →"),
    "账本是你自己的一个文件，放在你的 Mac 上（开了 iCloud 云盘就跟着 iCloud 走），不传到我们的服务器，也不需要银行密码。每次改动都有记录，随时能撤销。": ("The ledger is your own file on your Mac (with iCloud Drive turned on, it lives in your iCloud). It isn't uploaded to our servers and needs no bank password. Every change is recorded and can be undone.",
        "El libro es un archivo tuyo en tu Mac (con iCloud Drive activado, va en tu iCloud). No se sube a nuestros servidores ni necesita la contraseña del banco. Cada cambio queda registrado y se puede deshacer."),
    "Mac 上一屏看完，深浅色都好看。": ("One screen per page on Mac, good-looking in light and dark.",
        "En el Mac, cada página en una pantalla, bonita en claro y en oscuro."),
    "Mac 版用苹果原生组件做的，窗口拉大拉小都是一屏看完。下面的数字全是示例数据。": ("The Mac app is built with Apple's native components; resize the window and each page still fits on one screen. All numbers below are sample data, and the screenshots show the Chinese interface.",
        "La app de Mac está hecha con componentes nativos de Apple; cambia el tamaño de la ventana y cada página sigue cabiendo en una pantalla. Las cifras son datos de ejemplo y las capturas muestran la interfaz en chino."),
    "即将推出": ("Coming soon",
        "Muy pronto"),
    "口袋里，<br>也是同一本账。": ("In your pocket,<br>the same ledger.",
        "En tu bolsillo,<br>el mismo libro."),
    "开了 iCloud 云盘，iPhone 和 Mac 接上同一个「夏夏账本」文件夹，就会自动同步：在手机上记的，回到电脑上就看得到。iPhone 版还没公开下载，做好了会在这里通知。": ("With iCloud Drive turned on and both devices linked to the same Xiaxia Ledger folder, iPhone and Mac sync automatically: what you add on your phone shows up on your computer. The iPhone app isn't available to download yet; we'll announce it here when it's ready. Screenshots show the Chinese interface.",
        "Con iCloud Drive activado y los dos dispositivos enlazados a la misma carpeta de Xiaxia Ledger, el iPhone y el Mac se sincronizan solos: lo que apuntas en el móvil aparece en el ordenador. La app de iPhone aún no se puede descargar; lo anunciaremos aquí cuando esté lista. Las capturas muestran la interfaz en chino."),
    "随手记一笔": ("Quick entry",
        "Apunte rápido"),
    "打开就能记，金额、分类、账户点几下就好，还能「再记一笔」连着记。": ("Open it and add an entry: amount, category and account in a few taps, and “Add another” to keep going.",
        "Ábrela y apunta: importe, categoría y cuenta en unos toques, y «Apuntar otro» para seguir."),
    "拍小票": ("Snap the receipt",
        "Fotografía el tique"),
    "对着小票拍一张，或者说一句「午饭 10 欧」，先存进待记录，之后让夏夏补进账本。": ("Take a photo of a receipt or type “lunch 10 euros”; it waits in your to-do list until Xiaxia adds it to the ledger.",
        "Haz una foto al tique o escribe «comida 10 euros»; queda pendiente hasta que Xiaxia lo pase al libro."),
    "报销一页看清": ("Expense claims on one page",
        "Reembolsos en una página"),
    "哪些没交、哪些交了在等钱、哪些已经到账，一页看清，还能导出报销单。": ("What's not submitted, what's waiting to be paid and what's been paid, all on one page, and you can export a claim sheet.",
        "Qué falta por presentar, qué espera el pago y qué ya se cobró, todo en una página, y puedes exportar la hoja de reembolso."),
    "和 Mac 同步": ("Syncs with your Mac",
        "Se sincroniza con tu Mac"),
    "在 iPhone 上选一次 iCloud 云盘里的「夏夏账本」文件夹，就和 Mac 看同一本账，不用导来导去；总览、收支、家底、计划在手机上也都能看。": ("Pick the Xiaxia Ledger folder in iCloud Drive once on your iPhone and it shares one ledger with your Mac, no exporting back and forth; Overview, income and spending, net worth and plans are all on your phone too.",
        "Elige una vez en el iPhone la carpeta de Xiaxia Ledger en iCloud Drive y compartirá el mismo libro con tu Mac, sin exportar de un lado a otro; Resumen, ingresos y gastos, patrimonio y planes también están en el móvil."),
    "iPhone 上的「记一笔」：可以拍小票或说一句，下面是计算器键盘（示例数据）": ("Adding an entry on iPhone: snap a receipt or type a sentence, with a calculator keypad below (sample data)",
        "Apuntar en iPhone: fotografía un tique o escribe una frase, con teclado de calculadora debajo (datos de ejemplo)"),
    "iPhone 上的报销页：待提交、已提交、已到账分开列出（示例数据）": ("Expense claims on iPhone: not submitted, submitted and paid listed separately (sample data)",
        "Reembolsos en iPhone: por presentar, presentados y cobrados por separado (datos de ejemplo)"),
    "在手机上看？iPhone 版即将推出，可以先看看它能做什么；Mac 版要回到电脑上下载，先把网址发给自己就行。": ("On your phone? The iPhone app is coming soon; see what it can do below. The Mac app downloads on your computer, so send yourself this link.",
        "¿Estás en el móvil? La app de iPhone llega muy pronto; mira abajo lo que hace. La de Mac se descarga en el ordenador: envíate este enlace."),
    "看看 iPhone 版": ("See the iPhone app",
        "Ver la app de iPhone"),
    # 2026-11-26 按 apple-design 审计改的
    "左右滑动看整张截图": ("Swipe sideways to see the whole screenshot", "Desliza a los lados para ver la captura entera"),
    "/* 动效：按下立刻有反应；展开、弹出都从按的地方长出来。系统设了「减少动态效果」就全关。 */": ("/* motion: instant press feedback; menus and answers grow from where you tapped; all off with Reduce Motion */",)*2,
    "/* 系统设了「减少透明度」：顶栏改实色。「增强对比度」：边线和次要文字加深。 */": ("/* Reduce Transparency: solid nav. Increase Contrast: darker lines and secondary text */",)*2,
    "// 新图叠在旧图上淡入，换完再拿掉旧图：中间不会闪一下空白": ("// cross-fade the new screenshot over the old one",)*2,
    "// 先淡出，换图，加载好再淡入": ("// fade out, swap, fade in",)*2,
    "// 手机菜单：点了链接、点菜单外面、按 Esc 都收起": ("// phone menu: close on link, outside tap or Esc",)*2,
    "// 顶栏：往下滚了才出现分隔线": ("// nav: show the divider only after scrolling",)*2,
    "// 对话：滚到这里时一条条冒出来（减少动态效果时直接全显示）": ("// chat: reveal messages one by one (all at once with Reduce Motion)",)*2,
}
