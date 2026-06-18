extends Area2D
class_name Bullet

const WORLD_COLLISION_MASK := 1

# 子弹的速度
@export var speed: float = 320.0
# 子弹的最大寿命（秒）
@export var max_lifetime: float = 2.0

# 子弹的方向，默认为向右
var direction: Vector2 = Vector2.RIGHT
# 当前剩余寿命，到 0 自动销毁
var remaining_lifetime: float = 0.0

# 初始生命周期
func _ready() -> void:
    remaining_lifetime = max_lifetime
    area_entered.connect(_on_area_entered)

# 由外部在生成子弹后调用，注入初始方向
func setup(initial_direction: Vector2) -> void:
    if initial_direction != Vector2.ZERO:
        direction = initial_direction.normalized()

    rotation = direction.angle()

# 每帧先检测飞行路径是否会撞到世界，再更新位置并处理超时回收
func _physics_process(delta: float) -> void:
    var current_position := global_position
    var next_position := current_position + direction * speed * delta

    if _will_hit_world(current_position, next_position):
        queue_free()
        return

    global_position = next_position

    remaining_lifetime -= delta
    if remaining_lifetime <= 0.0:
        queue_free()
        return

# 使用射线查询检测当前这一帧的飞行路径，避免子弹穿过零厚度边界或薄墙体
func _will_hit_world(from_position: Vector2, to_position: Vector2) -> bool:
    var space_state := get_world_2d().direct_space_state
    if space_state == null:
        return false

    var query := PhysicsRayQueryParameters2D.create(
        from_position,
        to_position,
        WORLD_COLLISION_MASK
    )
    query.collide_with_bodies = true
    query.collide_with_areas = false

    var hit_result: Dictionary = space_state.intersect_ray(query)
    return not hit_result.is_empty()

func _on_area_entered(area: Area2D) -> void:
    if area is Bullet:
        return

    queue_free()