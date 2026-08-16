# Sparkle signing key

TrackpadGuard의 첫 외부 릴리스 전에 Sparkle의 `generate_keys` 도구로 앱 전용 키를 생성합니다.

```sh
.build/artifacts/sparkle/Sparkle/bin/generate_keys -a TrackpadGuard
```

출력된 공개 키만 `Configuration/SparklePublicKey.txt`에 저장합니다. 비공개 키는 로그인 Keychain의 `TrackpadGuard` 계정에만 보관하고 저장소나 셸 기록에 넣지 않습니다.
