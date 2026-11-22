# 夏夏和 AI 伙伴的形象

四个原创 Q 版角色，2026-11-22 用 ChatGPT 生图按文字描述画的（参考了网上「AI 拟人」这一类画风的感觉，没有照抄任何一张图，也没有任何官方 logo）：

| 角色 | 是谁 | 在 app 里出现的地方 |
|---|---|---|
| 夏夏 xiaxia | 主角，蓝发鲸鱼娘，女仆水手裙，抱小算盘 | 每页「夏夏说」卡片、空状态（打盹 / 担心 / 庆祝…）、设置里选性格、对话栏 |
| 小橘 orange | 橘发书本少女，Claude 系的伙伴 | AI 连接状态、「Claude 刚记了 N 笔」、对话栏里 Claude Code 在帮忙时 |
| 小紫 lilac | 小龙角少女，Codex / GPT 的伙伴 | 同上（Codex） |
| 小星 star | 星空少女，Gemini、Hermes 和其它 AI 的伙伴 | 同上（Gemini CLI、Hermes、Cursor…） |

## 动作

文件名是 `角色-动作.webp`，放在 `Sources/LedgerUI/Resources/Mascot/`。缺了的动作自动退回 `-idle`，加图就生效。

- 夏夏：idle（待机）、blink（眨眼帧）、talk（说话帧）、calm（文静）、cheer（打气）、sharp（毒舌）、think（在想）、write（记账）、worried（钱花超了）、celebrate（存钱成功）、sleep（睡着）、hello（打招呼）
- 伙伴：idle、blink、talk、think

四种性格：温和直说 = idle，毒舌 = sharp，文静 = calm，打气 = cheer。

## 怎么动

`MascotView`（Sources/LedgerUI/Mascot.swift）在 SwiftUI 里实时动：呼吸（上下轻微伸缩）、左右摆、开心的动作会蹦、担心会抖；每 3.7 秒眨一次眼；说话时嘴一张一合；身边飘星星、金币、汗珠、Zzz、泡泡。打开系统「减弱动态效果」就全部停下。

眨眼和说话帧不是整张换：ChatGPT 每次重画整张图会有细微偏差，所以用 `patch.py` 只把闭眼 / 张嘴那一小块（羽化的椭圆）贴回定稿图，换帧时身体纹丝不动。

## 重新生成

1. 原图（ChatGPT 下载的 1254×1254 透明 PNG）在项目文件夹 `mascot/raw/`，不进仓库。
2. 眨眼 / 说话（这次用的椭圆：夏夏眨眼 380 345 790 610、说话 530 530 700 640；小橘 370 370 815 625 / 555 555 715 645；小星 355 370 775 620 / 380 410 730 665；小紫 385 345 815 600 / 565 550 705 625，羽化都是 10）：`python3 design/mascot/patch.py 定稿.png 闭眼图.png 输出.png x0 y0 x1 y1 [羽化]`，坐标是眼睛（或嘴）那块的椭圆范围。
3. 全部放进一个文件夹（命名同上），`python3 design/mascot/build.py 那个文件夹`：缩成 640px WebP，并重新算头像要用的脸部位置（写进 `MascotData.swift`）。
4. 自动找脸偶尔会找错（比如庆祝图里的粉色存钱罐），在 build.py 的 `OVERRIDES` 里手动写位置。
