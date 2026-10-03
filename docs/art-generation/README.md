# 캐릭터 프레임 제작 원본

각 `<id>/` 폴더는 실제 전송 프롬프트와 생성 원본, 수리·검토 기록을 보존한다. `<state>.prompt.txt`와 `<state>.source.png`는 해당 상태의 제작 원본이며 런타임 채택 여부는 인덱스로 확인한다. `rejected`·`gait-candidate` 파일은 런타임 채택을 뜻하지 않는다. 수리 전 원본도 제작 근거로 유지한다.

제작·패킹·검증 절차는 [리소스 제작 안내](../RESOURCE_GUIDE.md)에 통합한다. 필수 상태와 정체성 계약은 [identity-plan.json](../../tools/art/identity-plan.json), 실제 런타임 연결은 [identity_animations.json](../../assets/art/identity_animations.json), 미결은 [REMAINING](../REMAINING.md)을 따른다.

프롬프트 준비·가져오기 도구와 리소스 receipt가 이 경로를 직접 사용하므로 임의 이동·삭제하지 않는다. 이 폴더는 `.gdignore`로 Godot 가져오기에서 제외되며 게임은 `assets/art/identities/`의 아틀라스를 사용한다.
