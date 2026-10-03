# 개별 캐릭터 프레임 제작 원본

각 폴더의 `<state>.prompt.txt`는 내장 이미지 도구에 실제 전송한 sprite-gen 기반 프롬프트이며, `<state>.source.png`는 그 생성 결과 원본이다. 수리한 경우 원본과 수리 프롬프트를 따로 보존한다. 제작 범위는 `docs/RESOURCE_UPGRADE_PLAN.md`와 `tools/art/identity-plan.json`을 참고한다. 계획에 등장한다는 사실만으로 제작 완료를 뜻하지 않는다.

외부 GPT/Grok API를 호출하지 않았다. sprite-gen의 기존 중간 프롬프트와 검증된 `row_prompt()` 템플릿을 사용하며, 새 CLI 실행으로 프롬프트를 추출했다고 주장하지 않는다. 실제 사용한 원본: https://github.com/aldegad/sprite-gen/blob/4a2ebdbcbb9e228b143ef10876ecd48261288df0/sprite_gen/gen/prepare.py#L753-L826

내장 이미지 도구에는 모델 ID 선택 기능이 없으며, 생성 모델 ID/등급을 추정하지 않는다. 작업 추론 모델과 이미지 생성 모델은 별개다.

## 파이프라인

1. 실제 `assets/art/portraits/<id>.png`를 눈으로 확인한다
2. `python3 tools/art/prepare_identity_prompts.py <id> --state attack|walk|idle`로 보존된 sprite-gen 템플릿에 해당 개체의 동작/정체성 계약을 적용한다
3. 원화와 `layout-guide-3x2.png`를 참고해 내장 이미지 도구로 실제 새 자세를 생성한다
4. 원본에서 무기/의상/얼굴/팔다리/여백/프레임별 동작을 시각 검토한다. 필요하면 내장 도구로 수리하고 실제 수리 프롬프트도 보존한다
5. `python3 tools/art/import_identity.py <id> --state <state>`로 독립된 여섯 자세를 균일 배율로 패킹한다. 정체성에 부유 장식이 있으면 `--ornaments`, 완전한 3×2 구획이 확보된 경우 `--grid`를 사용한다
6. 실제 런타임 경로와 해시/타이밍은 `assets/art/identity_animations.json` 및 각 개체의 `layout.json`, `receipt.json`에 기록된다
7. `python3 tools/art/test_import_identity.py`, `bash scripts/verify.sh`, 실제 화면의 `tests/identity_visual_scenario.gd`, UI 및 Web 검사를 실행한다

패킹 도구는 Python3, Pillow, NumPy, SciPy가 필요하다. 기존 자세를 회전시켜 새 프레임으로 위장하지 않으며, 원본의 독립된 자세를 잘라내어 하나의 균일 배율/발 기준점으로 배열한다. 기존 상태를 보존하면서 새 상태를 병합한다. 원본 그림 자체를 이 도구로 다시 그리지 않는다.

이 폴더는 `.gdignore`로 Godot 자동 리소스 가져오기에서 제외된다. 게임은 `assets/art/identities`의 정규화된 아틀라스만 사용한다.
