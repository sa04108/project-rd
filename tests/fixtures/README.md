# 0.2 저장 호환 fixture

`content-v0.2.0.json`은 커밋 `5e4c716`의 `game/simulation.gd`,
`game/catalog.gd`, `data/*.json`을 별도 임시 Godot 프로젝트로 복사한 뒤
Godot 4.4.1에서 직접 만든 출력이다. 현 버전 저장의 버전 문자열만 바꾼 파일이 아니다.

생성 순서:

1. `new_run(913)`, `debug_jump_wave(31)`, `summon()` 두 번.
2. `add_enemy("n02", 31)`의 HP를 3.25 낮추고 진행도를 2.5로 설정.
3. `snapshot()`을 `normal`로 보관하고 다음 `rng.randi()`를 `next_rng_draw`로 기록.
4. `restore(normal)` 뒤 적이 55마리가 될 때까지 `add_enemy("n02", 31)`을 호출하여 `crowded`로 보관.

원본 fixture에는 개발 판 표시가 있다. UI 검사는 이 fixture의 복사본에서
`developer_run=false`와 고유 run ID를 사용하여 일반 프로필의 최고 웨이브·종료 ID 기록 경로도 검사한다.
라이브 HP/위치/개체 ID/난수 상태는 바꾸지 않는다.
