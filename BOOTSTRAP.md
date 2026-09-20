# woni_app 하네스 부트스트랩

AI 하네스 파일은 이 저장소가 아니라 **별도 저장소**(`woniApp_ai_settings`)의 `ios/` 하위에 있고,
`.ai-context/` 에 **일반 클론**으로 둔다. 서브모듈이 **아니다**. 루트의 `CLAUDE.md`·`AGENTS.md`·`.claude`
symlink 가 깨져 있으면 아래로 초기화한다.

```bash
git clone https://github.com/leejungkuk/woniApp_ai_settings.git .ai-context
cd .ai-context
git sparse-checkout init --cone
git sparse-checkout set .github backend ios shared
cd ..
```

`.ai-context/` 는 `.gitignore` 에 있으므로 이 저장소에 커밋되지 않는다.

하네스 본문 위치:

- `.ai-context/ios/.claude` (← `.claude`)
- `.ai-context/ios/.claude/CLAUDE.md` (← `CLAUDE.md`)
- `.ai-context/ios/AGENTS.md` (← `AGENTS.md`)

## 왜 서브모듈이 아닌가

2026-09-20 에 걷어냈다. 근거는 측정이다.

- 커밋된 포인터가 **230커밋** 뒤처져 있었고, 하네스 재구축 **이전**을 가리켰다. 즉 새로 클론하면
  이미 지운 구 하네스(`ios/.codex/`·`codex-quota.py` 등)를 받았다. 로컬에서는 symlink 가 **작업 트리**를
  가리켜 정상 동작했으므로 증상이 보이지 않았다.
- 이 저장소는 **public** 인데 하네스는 **private** 이다. 제3자는 `submodule update --init` 이 인증
  실패해 애초에 받을 수 없었다.
- 양쪽 CI 어느 워크플로도 서브모듈을 체크아웃하지 않는다(`build.yml` 은 "프라이빗 토큰 회피"로 명시).
- `main` 이 `enforce_admins: true` + 필수 체크 `build` 라, 포인터 1줄 PR 마다 전체 iOS 빌드가 돌았다.
  하네스는 26일간 230커밋(하루 ~9건) 페이스라 따라갈 수 없었다.

용량 때문이 아니다 — 서브모듈 제거로 줄어드는 추적 용량은 127바이트다. **드리프트를 없애는 게 목적이다.**

## 하네스를 고칠 때

`.ai-context` 는 독립 저장소다. 거기서 브랜치를 따고 커밋·PR 한다. **이 저장소에는 아무 기록도 남지
않는다** — 그게 의도다. 하네스 버전을 앱 커밋에 묶지 않는다.
