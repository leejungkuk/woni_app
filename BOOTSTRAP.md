# woni_app 하네스 부트스트랩

이 저장소는 AI 하네스 파일을 `.ai-context` 서브모듈의 `ios/` 하위에서 관리합니다. fresh clone 이후 루트의 `CLAUDE.md`, `AGENTS.md`, `.claude`, `.codex` symlink가 깨져 있으면 아래 순서로 초기화합니다.

```bash
git submodule update --init .ai-context
cd .ai-context
git sparse-checkout init --cone
git sparse-checkout set ios
cd ..
```

하네스 본문 위치:

- `.ai-context/ios/.claude`
- `.ai-context/ios/.codex`
- `.ai-context/ios/AGENTS.md`

주의: `.claude/phases` 등 하네스 메타데이터는 서브모듈 내부 변경입니다. 슈퍼프로젝트 커밋과 별도로 `.ai-context` 서브모듈에서 상태를 확인하고 커밋해야 합니다.
