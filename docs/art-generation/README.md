# 캐릭터 프레임 제작 원본

각 `<id>/` 폴더는 실제 전송 프롬프트와 생성 원본, 수리·검토 기록을 보존한다. `<state>.prompt.txt`와 `<state>.source.png`는 해당 상태의 제작 근거이며 런타임 채택 여부는 인덱스로 확인한다. `rejected`·`gait-candidate` 파일은 채택을 뜻하지 않으며 수리 전 후보도 출처로 유지한다.

제작·패킹·용량 최적화·검증 절차는 [리소스 제작 안내](../RESOURCE_GUIDE.md)에 통합한다. 필수 상태와 정체성 계약은 [identity-plan.json](../../tools/art/identity-plan.json), 실제 런타임 연결은 [identity_animations.json](../../assets/art/identity_animations.json), 미결은 [REMAINING](../REMAINING.md)을 따른다.

일부 제작 PNG는 완전 투명 영역의 RGB 정리와 재압축을 거친 파생본이다. 생성 당시 바이트와 현재 바이트, 알파·가시 RGB 보존 계약은 [source-optimization.json](source-optimization.json)과 각 리소스 receipt에 기록한다. 프롬프트 준비·가져오기 도구와 receipt가 이 경로를 직접 사용하므로 임의 이동·삭제하지 않는다.

이 폴더는 `.gdignore`로 Godot 가져오기에서 제외되며 게임은 `assets/art/identities/`의 정규화된 아틀라스를 사용한다. 일회성 검사 보고서·실행 캡처는 `artifacts/`에 둔다.
