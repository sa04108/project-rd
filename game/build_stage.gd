class_name BuildStage
extends RefCounted

## 저장소의 편집기 실행은 운영 기본값을 사용하며, 내보내기 전에 전용 사본에서만 바꾼다.
const NAME: String = "production"
const SAVE_DIRECTORY: String = "user://"
const STARTER_DIAMONDS: int = 100
const DEVELOPMENT: bool = false
