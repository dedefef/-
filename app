import pygame
import math
import random
import sys

# ==========================================
# 1. 초기 설정 및 상수 정의
# ==========================================
pygame.init()
WIDTH, HEIGHT = 1280, 720
screen = pygame.display.set_mode((WIDTH, HEIGHT))
pygame.display.set_caption("Mini LoL - 칼바람 단일 라인 교전 (Python Pygame)")
clock = pygame.time.Clock()
FPS = 60

# 색상 팔레트 (롤 인터페이스 느낌)
BG_COLOR = (24, 34, 45)         # 어두운 협곡 바닥
LANE_COLOR = (38, 50, 64)       # 라인 길바닥
BUSH_COLOR = (22, 74, 52)       # 부쉬 색상
BLUE_TEAM = (10, 165, 233)      # 블루팀 (플레이어)
RED_TEAM = (239, 68, 68)        # 레드팀 (적)
GOLD_COLOR = (234, 179, 8)      # 골드 / UI 테두리
HP_GREEN = (34, 197, 94)
MANA_BLUE = (59, 130, 246)
WHITE = (248, 250, 252)
DARK_UI = (15, 23, 42)

# 폰트 설정 (한글 깨짐 방지용 기본 시스템 폰트 탐색)
def get_font(size, bold=False):
    font_names = ['malgungothic', 'applegothic', 'nanumgothic', 'arial']
    for name in font_names:
        matched = pygame.font.match_font(name, bold=bold)
        if matched:
            return pygame.font.Font(matched, size)
    return pygame.font.SysFont(None, size, bold=bold)

font_sm = get_font(14)
font_md = get_font(18, True)
font_lg = get_font(36, True)
font_dmg = get_font(16, True)

# ==========================================
# 2. 유틸리티 및 이펙트 클래스
# ==========================================
class FloatingText:
    """데미지, 골드 획득, 레벨업 텍스트 팝업"""
    def __init__(self, x, y, text, color):
        self.x = x + random.randint(-10, 10)
        self.y = y - 20
        self.text = text
        self.color = color
        self.timer = 45
        self.alpha = 255

    def update(self):
        self.y -= 0.8
        self.timer -= 1
        self.alpha = max(0, int((self.timer / 45) * 255))

    def draw(self, surf):
        txt_surf = font_dmg.render(self.text, True, self.color)
        txt_surf.set_alpha(self.alpha)
        surf.blit(txt_surf, (self.x - txt_surf.get_width() // 2, self.y))

class Particle:
    """타격 및 스킬 폭발 파티클"""
    def __init__(self, x, y, color, speed_range=(1, 4), size_range=(3, 7), life=25):
        self.x = x
        self.y = y
        angle = random.uniform(0, math.pi * 2)
        speed = random.uniform(*speed_range)
        self.vx = math.cos(angle) * speed
        self.vy = math.sin(angle) * speed
        self.color = color
        self.size = random.randint(*size_range)
        self.life = life
        self.max_life = life

    def update(self):
        self.x += self.vx
        self.y += self.vy
        self.life -= 1
        self.size = max(1, self.size * (self.life / self.max_life))

    def draw(self, surf):
        pygame.draw.circle(surf, self.color, (int(self.x), int(self.y)), int(self.size))

class ClickMarker:
    """우클릭 이동/공격 바닥 표시 이펙트"""
    def __init__(self, x, y, is_attack=False):
        self.x = x
        self.y = y
        self.timer = 20
        self.color = RED_TEAM if is_attack else HP_GREEN

    def update(self):
        self.timer -= 1

    def draw(self, surf):
        radius = int(18 * (self.timer / 20))
        pygame.draw.circle(surf, self.color, (int(self.x), int(self.y)), radius, 2)

# ==========================================
# 3. 투사체 (평타, 스킬샷) 클래스
# ==========================================
class Projectile:
    def __init__(self, x, y, team, speed, damage, radius, color, target=None, angle=None, max_range=600, skill_type="normal"):
        self.x = x
        self.y = y
        self.start_x = x
        self.start_y = y
        self.team = team
        self.speed = speed
        self.damage = damage
        self.radius = radius
        self.color = color
        self.target = target          # 유도탄일 경우 타겟 객체
        self.angle = angle            # 논타겟 스킬샷일 경우 각도
        self.max_range = max_range
        self.skill_type = skill_type  # "normal", "Q", "W", "R"
        self.alive = True
        self.hit_list = []            # 관통 스킬 중복 피격 방지

    def update(self, entities, particles, floating_texts, owner):
        if not self.alive:
            return

        # 유도 투사체 (평타 / 포탑 공격)
        if self.target:
            if not self.target.alive:
                self.alive = False
                return
            dx = self.target.x - self.x
            dy = self.target.y - self.y
            dist = math.hypot(dx, dy)
            if dist < self.target.radius + self.radius:
                self.on_hit(self.target, particles, floating_texts, owner)
                self.alive = False
                return
            self.x += (dx / dist) * self.speed
            self.y += (dy / dist) * self.speed

        # 논타겟 직선 투사체 (Q, W, R)
        else:
            self.x += math.cos(self.angle) * self.speed
            self.y += math.sin(self.angle) * self.speed

            if math.hypot(self.x - self.start_x, self.y - self.start_y) >= self.max_range:
                self.alive = False
                return

            for ent in entities:
                if ent.alive and ent.team != self.team and ent not in self.hit_list:
                    if math.hypot(ent.x - self.x, ent.y - self.y) < ent.radius + self.radius:
                        self.on_hit(ent, particles, floating_texts, owner)
                        self.hit_list.append(ent)
                        if self.skill_type == "Q":  # Q는 첫 대상 적중 시 소멸
                            self.alive = False
                            return

    def on_hit(self, target, particles, floating_texts, owner):
        target.take_damage(self.damage, owner, floating_texts, particles)
        if self.skill_type == "W":
            target.slow_timer = 120  # 2초 둔화
            floating_texts.append(FloatingText(target.x, target.y - 15, "둔화!", (147, 197, 253)))
        for _ in range(8 if self.skill_type == "normal" else 18):
            particles.append(Particle(self.x, self.y, self.color))

    def draw(self, surf):
        pygame.draw.circle(surf, self.color, (int(self.x), int(self.y)), self.radius)
        pygame.draw.circle(surf, WHITE, (int(self.x), int(self.y)), max(2, self.radius // 2))

# ==========================================
# 4. 유닛 기본 클래스 (챔피언, 미니언, 포탑)
# ==========================================
class Entity:
    def __init__(self, x, y, team, max_hp, radius, speed, atk_dmg, atk_range, atk_cd, gold_reward=20):
        self.x = x
        self.y = y
        self.team = team
        self.max_hp = max_hp
        self.hp = max_hp
        self.radius = radius
        self.base_speed = speed
        self.atk_dmg = atk_dmg
        self.atk_range = atk_range
        self.atk_cd = atk_cd
        self.atk_timer = 0
        self.slow_timer = 0
        self.alive = True
        self.gold_reward = gold_reward

    @property
    def speed(self):
        return self.base_speed * (0.5 if self.slow_timer > 0 else 1.0)

    def take_damage(self, amount, attacker, floating_texts, particles):
        if not self.alive:
            return
        self.hp -= amount
        floating_texts.append(FloatingText(self.x, self.y, f"-{int(amount)}", (255, 100, 100)))
        if self.hp <= 0:
            self.hp = 0
            self.alive = False
            for _ in range(25):
                particles.append(Particle(self.x, self.y, RED_TEAM if self.team == "RED" else BLUE_TEAM, (2, 6), (4, 9), 35))
            if isinstance(attacker, Champion):
                attacker.gold += self.gold_reward
                attacker.gain_xp(self.gold_reward * 1.5, floating_texts)
                floating_texts.append(FloatingText(self.x, self.y - 25, f"+{self.gold_reward}G", GOLD_COLOR))

    def draw_hp_bar(self, surf, width=50, height=7, offset_y=-35):
        bar_x = self.x - width // 2
        bar_y = self.y + offset_y
        pygame.draw.rect(surf, (15, 23, 42), (bar_x - 1, bar_y - 1, width + 2, height + 2))
        ratio = max(0, self.hp / self.max_hp)
        color = BLUE_TEAM if self.team == "BLUE" else RED_TEAM
        pygame.draw.rect(surf, color, (bar_x, bar_y, int(width * ratio), height))

# ==========================================
# 5. 챔피언 클래스 (플레이어 & 적 AI 챔피언)
# ==========================================
class Champion(Entity):
    def __init__(self, x, y, team, name, is_player=False):
        super().__init__(x, y, team, max_hp=650, radius=22, speed=3.6, atk_dmg=62, atk_range=240, atk_cd=48, gold_reward=300)
        self.name = name
        self.is_player = is_player
        self.max_mana = 350
        self.mana = 350
        self.level = 1
        self.xp = 0
        self.max_xp = 100
        self.gold = 500
        self.kills = 0
        self.deaths = 0
        self.respawn_timer = 0

        # 이동 및 공격 타겟
        self.target_pos = (x, y)
        self.attack_target = None

        # 스킬 쿨타임 (프레임 단위, 60 = 1초)
        self.cd = {"Q": 0, "W": 0, "E": 0, "R": 0}
        self.max_cd = {"Q": 180, "W": 360, "E": 480, "R": 900}
        self.mana_cost = {"Q": 45, "W": 65, "E": 50, "R": 100}

    def gain_xp(self, amount, floating_texts):
        self.xp += amount
        if self.xp >= self.max_xp and self.level < 18:
            self.xp -= self.max_xp
            self.level += 1
            self.max_xp = int(self.max_xp * 1.25)
            self.max_hp += 85
            self.hp = min(self.max_hp, self.hp + 150)
            self.max_mana += 40
            self.mana = min(self.max_mana, self.mana + 100)
            self.atk_dmg += 6
            floating_texts.append(FloatingText(self.x, self.y - 40, f"LEVEL UP! ({self.level})", GOLD_COLOR))

    def respawn(self):
        self.alive = True
        self.hp = self.max_hp
        self.mana = self.max_mana
        self.x = 120 if self.team == "BLUE" else WIDTH - 120
        self.y = HEIGHT // 2
        self.target_pos = (self.x, self.y)
        self.attack_target = None

    def cast_skill(self, key, mouse_pos, projectiles, particles, floating_texts):
        if not self.alive or self.cd[key] > 0 or self.mana < self.mana_cost[key]:
            return

        angle = math.atan2(mouse_pos[1] - self.y, mouse_pos[0] - self.x)
        self.mana -= self.mana_cost[key]
        self.cd[key] = self.max_cd[key]

        if key == "Q":  # 신비한 화살 (빠른 직선 투사체)
            dmg = self.atk_dmg * 1.45 + self.level * 12
            proj = Projectile(self.x, self.y, self.team, 13, dmg, 9, (56, 189, 248), angle=angle, max_range=520, skill_type="Q")
            projectiles.append(proj)

        elif key == "W":  # 정수 흐름 (관통 + 둔화 장풍)
            dmg = self.atk_dmg * 1.1 + self.level * 10
            proj = Projectile(self.x, self.y, self.team, 9, dmg, 18, (168, 85, 247), angle=angle, max_range=440, skill_type="W")
            projectiles.append(proj)

        elif key == "E":  # 비전 이동 (마우스 방향으로 점멸!)
            dash_dist = 165
            new_x = max(40, min(WIDTH - 40, self.x + math.cos(angle) * dash_dist))
            new_y = max(140, min(HEIGHT - 160, self.y + math.sin(angle) * dash_dist))
            for _ in range(15):
                particles.append(Particle(self.x, self.y, (250, 204, 21)))
            self.x, self.y = new_x, new_y
            self.target_pos = (self.x, self.y)
            for _ in range(15):
                particles.append(Particle(self.x, self.y, (250, 204, 21)))

        elif key == "R":  # 정조준 일격 (초장거리 대형 관통 궁극기)
            dmg = self.atk_dmg * 2.4 + self.level * 25
            proj = Projectile(self.x, self.y, self.team, 15, dmg, 26, (250, 204, 21), angle=angle, max_range=1300, skill_type="R")
            projectiles.append(proj)
            floating_texts.append(FloatingText(self.x, self.y - 30, "정조준 일격!", (250, 204, 21)))

    def update(self, entities, projectiles, particles, floating_texts):
        if not self.alive:
            self.respawn_timer -= 1
            if self.respawn_timer <= 0:
                self.respawn()
            return

        # 쿨타임 및 재생 처리
        for k in self.cd:
            if self.cd[k] > 0:
                self.cd[k] -= 1
        if self.atk_timer > 0:
            self.atk_timer -= 1
        if self.slow_timer > 0:
            self.slow_timer -= 1

        # 우물(본진) 근처 빠른 회복 + 기본 마나/체력 재생
        in_fountain = (self.team == "BLUE" and self.x < 160) or (self.team == "RED" and self.x > WIDTH - 160)
        self.hp = min(self.max_hp, self.hp + (4.0 if in_fountain else 0.08))
        self.mana = min(self.max_mana, self.mana + (5.0 if in_fountain else 0.25))

        # AI 챔피언 로직 (적 챔피언)
        if not self.is_player:
            self.run_ai(entities, projectiles, particles, floating_texts)

        # 공격 타겟이 있는 경우 추격 및 평타
        if self.attack_target and self.attack_target.alive:
            dist = math.hypot(self.attack_target.x - self.x, self.attack_target.y - self.y)
            if dist <= self.atk_range:
                self.target_pos = (self.x, self.y)  # 사거리 안이면 멈춰서 공격
                if self.atk_timer <= 0:
                    self.atk_timer = self.atk_cd
                    color = (125, 211, 252) if self.team == "BLUE" else (252, 165, 165)
                    projectiles.append(Projectile(self.x, self.y, self.team, 11, self.atk_dmg, 6, color, target=self.attack_target))
            else:
                self.target_pos = (self.attack_target.x, self.attack_target.y)
        else:
            self.attack_target = None

        # 이동 처리
        dx = self.target_pos[0] - self.x
        dy = self.target_pos[1] - self.y
        dist = math.hypot(dx, dy)
        if dist > self.speed:
            self.x += (dx / dist) * self.speed
            self.y += (dy / dist) * self.speed

    def run_ai(self, entities, projectiles, particles, floating_texts):
        """적 챔피언 AI: 거리 유지(카이팅), 스킬 사용, 체력 낮으면 후퇴"""
        # 체력이 28% 이하면 본진으로 후퇴
        if self.hp < self.max_hp * 0.28:
            self.attack_target = None
            self.target_pos = (WIDTH - 100, HEIGHT // 2)
            return

        # 가장 가까운 적 탐색
        enemies = [e for e in entities if e.alive and e.team != self.team]
        if not enemies:
            return
        nearest = min(enemies, key=lambda e: math.hypot(e.x - self.x, e.y - self.y))
        dist = math.hypot(nearest.x - self.x, nearest.y - self.y)

        # 사거리 내 적에게 스킬 난사
        if dist < 480 and self.cd["Q"] == 0:
            self.cast_skill("Q", (nearest.x, nearest.y), projectiles, particles, floating_texts)
        if dist < 400 and self.cd["W"] == 0:
            self.cast_skill("W", (nearest.x, nearest.y), projectiles, particles, floating_texts)
        if isinstance(nearest, Champion) and nearest.hp < nearest.max_hp * 0.5 and self.cd["R"] == 0:
            self.cast_skill("R", (nearest.x, nearest.y), projectiles, particles, floating_texts)

        # 적당히 거리 유지하며 교전
        if dist < self.atk_range * 0.75:
            self.attack_target = None
            self.target_pos = (min(WIDTH - 100, self.x + 80), HEIGHT // 2 + random.randint(-40, 40))
        elif dist <= self.atk_range + 150:
            self.attack_target = nearest
        else:
            self.attack_target = None
            self.target_pos = (nearest.x + 180, nearest.y)

    def draw(self, surf):
        if not self.alive:
            return
        # 평타 사거리 은은하게 표시 (플레이어만)
        if self.is_player:
            pygame.draw.circle(surf, (45, 65, 85), (int(self.x), int(self.y)), self.atk_range, 1)

        color = BLUE_TEAM if self.team == "BLUE" else RED_TEAM
        pygame.draw.circle(surf, color, (int(self.x), int(self.y)), self.radius)
        pygame.draw.circle(surf, GOLD_COLOR, (int(self.x), int(self.y)), self.radius, 3)

        # 레벨 및 이름 표시
        lvl_txt = font_sm.render(f"Lv.{self.level} {self.name}", True, WHITE)
        surf.blit(lvl_txt, (self.x - lvl_txt.get_width() // 2, self.y - 54))
        self.draw_hp_bar(surf, width=64, height=8, offset_y=-36)

        # 마나바
        bar_x = self.x - 32
        bar_y = self.y - 27
        pygame.draw.rect(surf, (15, 23, 42), (bar_x, bar_y, 64, 4))
        pygame.draw.rect(surf, MANA_BLUE, (bar_x, bar_y, int(64 * (self.mana / self.max_mana)), 4))

# ==========================================
# 6. 미니언 & 포탑 클래스
# ==========================================
class Minion(Entity):
    def __init__(self, x, y, team, is_ranged=False):
        hp = 210 if is_ranged else 320
        dmg = 22 if is_ranged else 15
        rng = 170 if is_ranged else 45
        super().__init__(x, y, team, max_hp=hp, radius=13, speed=1.9, atk_dmg=dmg, atk_range=rng, atk_cd=65, gold_reward=25)
        self.is_ranged = is_ranged

    def update(self, entities, projectiles, particles, floating_texts):
        if not self.alive:
            return
        if self.atk_timer > 0:
            self.atk_timer -= 1
        if self.slow_timer > 0:
            self.slow_timer -= 1

        enemies = [e for e in entities if e.alive and e.team != self.team]
        target = None
        if enemies:
            nearest = min(enemies, key=lambda e: math.hypot(e.x - self.x, e.y - self.y))
            if math.hypot(nearest.x - self.x, nearest.y - self.y) <= 280:
                target = nearest

        if target:
            dist = math.hypot(target.x - self.x, target.y - self.y)
            if dist <= self.atk_range:
                if self.atk_timer <= 0:
                    self.atk_timer = self.atk_cd
                    if self.is_ranged:
                        c = BLUE_TEAM if self.team == "BLUE" else RED_TEAM
                        projectiles.append(Projectile(self.x, self.y, self.team, 7, self.atk_dmg, 4, c, target=target))
                    else:
                        target.take_damage(self.atk_dmg, self, floating_texts, particles)
            else:
                self.x += ((target.x - self.x) / dist) * self.speed
                self.y += ((target.y - self.y) / dist) * self.speed
        else:
            # 라인 전진
            dir_x = 1 if self.team == "BLUE" else -1
            self.x += dir_x * self.speed
            # 중앙 Y축으로 자연스럽게 정렬
            if abs(self.y - HEIGHT // 2) > 5:
                self.y += (1 if HEIGHT // 2 > self.y else -1) * 0.5

    def draw(self, surf):
        if not self.alive:
            return
        color = (56, 189, 248) if self.team == "BLUE" else (248, 113, 113)
        if self.is_ranged:
            # 원거리 미니언은 삼각형 모양
            pts = [(self.x, self.y - 14), (self.x - 12, self.y + 10), (self.x + 12, self.y + 10)]
            pygame.draw.polygon(surf, color, pts)
        else:
            pygame.draw.circle(surf, color, (int(self.x), int(self.y)), self.radius)
        self.draw_hp_bar(surf, width=30, height=4, offset_y=-20)

class Turret(Entity):
    def __init__(self, x, y, team, is_nexus=False):
        hp = 2500 if is_nexus else 1600
        super().__init__(x, y, team, max_hp=hp, radius=36 if is_nexus else 28, speed=0, atk_dmg=95, atk_range=270, atk_cd=75, gold_reward=250)
        self.is_nexus = is_nexus
        self.current_target = None

    def update(self, entities, projectiles, particles, floating_texts):
        if not self.alive:
            return
        if self.atk_timer > 0:
            self.atk_timer -= 1

        # 기존 타겟이 살아있고 사거리 내면 유지 (롤 포탑 어그로 시스템)
        if self.current_target and self.current_target.alive:
            if math.hypot(self.current_target.x - self.x, self.current_target.y - self.y) > self.atk_range:
                self.current_target = None
        else:
            self.current_target = None

        if not self.current_target:
            enemies = [e for e in entities if e.alive and e.team != self.team and math.hypot(e.x - self.x, e.y - self.y) <= self.atk_range]
            if enemies:
                # 미니언 우선 타겟팅
                minions = [e for e in enemies if isinstance(e, Minion)]
                self.current_target = minions[0] if minions else enemies[0]

        if self.current_target and self.atk_timer <= 0:
            self.atk_timer = self.atk_cd
            c = (250, 204, 21)
            projectiles.append(Projectile(self.x, self.y, self.team, 9, self.atk_dmg, 9, c, target=self.current_target))

    def draw(self, surf):
        if not self.alive:
            return
        # 포탑 사거리 표시
        ring_color = (30, 58, 95) if self.team == "BLUE" else (95, 30, 40)
        pygame.draw.circle(surf, ring_color, (int(self.x), int(self.y)), self.atk_range, 1)

        # 포탑 타겟 레이저 표시
        if self.current_target and self.current_target.alive:
            pygame.draw.line(surf, (250, 204, 21), (self.x, self.y), (self.current_target.x, self.current_target.y), 2)

        color = BLUE_TEAM if self.team == "BLUE" else RED_TEAM
        rect = pygame.Rect(self.x - self.radius, self.y - self.radius, self.radius * 2, self.radius * 2)
        pygame.draw.rect(surf, color, rect, border_radius=8)
        pygame.draw.rect(surf, GOLD_COLOR, rect, 3, border_radius=8)

        label = "넥서스" if self.is_nexus else "포탑"
        txt = font_sm.render(label, True, WHITE)
        surf.blit(txt, (self.x - txt.get_width() // 2, self.y - 8))
        self.draw_hp_bar(surf, width=80, height=9, offset_y=-self.radius - 16)

# ==========================================
# 7. 하단 HUD (롤 스타일 스킬창 & 상점 UI)
# ==========================================
def draw_hud(surf, player, game_time):
    hud_h = 110
    hud_y = HEIGHT - hud_h
    # 하단 바 배경
    pygame.draw.rect(surf, DARK_UI, (0, hud_y, WIDTH, hud_h))
    pygame.draw.line(surf, GOLD_COLOR, (0, hud_y), (WIDTH, hud_y), 2)

    # 왼쪽: 챔피언 스탯 & 골드
    stats = [
        f"챔피언: {player.name} (Lv.{player.level})",
        f"공격력: {int(player.atk_dmg)}   사거리: {player.atk_range}",
        f"보유 골드: {player.gold} G  [B키: 공격력 강화 (300G)]"
    ]
    for i, s in enumerate(stats):
        c = GOLD_COLOR if i == 2 else WHITE
        surf.blit(font_md.render(s, True, c), (25, hud_y + 16 + i * 28))

    # 중앙: Q, W, E, R 스킬 아이콘 및 쿨타임 표시
    skills = [("Q", "신비한 화살"), ("W", "정수 흐름"), ("E", "비전 이동"), ("R", "정조준 일격")]
    start_x = WIDTH // 2 - 170
    for idx, (key, name) in enumerate(skills):
        bx = start_x + idx * 90
        by = hud_y + 15
        box_rect = pygame.Rect(bx, by, 72, 72)

        # 마나 부족 또는 쿨타임 색상 처리
        if player.cd[key] > 0:
            bg = (30, 41, 59)
        elif player.mana < player.mana_cost[key]:
            bg = (30, 58, 138)
        else:
            bg = (14, 116, 144)

        pygame.draw.rect(surf, bg, box_rect, border_radius=6)
        pygame.draw.rect(surf, GOLD_COLOR, box_rect, 2, border_radius=6)

        # 단축키 & 마나 소모량
        surf.blit(font_md.render(key, True, GOLD_COLOR), (bx + 6, by + 4))
        surf.blit(font_sm.render(f"{player.mana_cost[key]}", True, (147, 197, 253)), (bx + 44, by + 50))

        # 쿨타임 숫자 오버레이
        if player.cd[key] > 0:
            sec = math.ceil(player.cd[key] / FPS)
            cd_txt = font_lg.render(str(sec), True, WHITE)
            surf.blit(cd_txt, (bx + 36 - cd_txt.get_width() // 2, by + 16))

    # 오른쪽 상단: 타이머 & 조작법 안내
    mins = game_time // (FPS * 60)
    secs = (game_time // FPS) % 60
    timer_surf = font_md.render(f"경과 시간 {mins:02d}:{secs:02d}", True, WHITE)
    surf.blit(timer_surf, (WIDTH - 170, 15))

    guide = "우클릭: 이동/공격 | Q,W,E,R: 마우스 방향 스킬 | S: 정지 | B: 무기 강화"
    surf.blit(font_sm.render(guide, True, (148, 163, 184)), (WIDTH - 460, hud_y + 45))

# ==========================================
# 8. 메인 게임 루프
# ==========================================
def main():
    player = Champion(180, HEIGHT // 2, "BLUE", "이즈리얼", is_player=True)
    enemy_champ = Champion(WIDTH - 180, HEIGHT // 2, "RED", "럭스", is_player=False)

    # 포탑 및 넥서스 배치
    blue_turret = Turret(360, HEIGHT // 2, "BLUE", is_nexus=False)
    blue_nexus = Turret(110, HEIGHT // 2, "BLUE", is_nexus=True)
    red_turret = Turret(WIDTH - 360, HEIGHT // 2, "RED", is_nexus=False)
    red_nexus = Turret(WIDTH - 110, HEIGHT // 2, "RED", is_nexus=True)

    entities = [player, enemy_champ, blue_turret, blue_nexus, red_turret, red_nexus]
    projectiles = []
    particles = []
    floating_texts = []
    click_markers = []

    wave_timer = 0
    game_time = 0
    game_over = None

    while True:
        clock.tick(FPS)
        mouse_pos = pygame.mouse.get_pos()

        # 이벤트 처리
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                pygame.quit()
                sys.exit()

            if game_over and event.type == pygame.KEYDOWN and event.key == pygame.K_r:
                main()  # 재시작
                return

            if not game_over and player.alive:
                # 우클릭: 이동 및 타겟 공격 (LoL 조작 방식)
                if event.type == pygame.MOUSEBUTTONDOWN and event.button == 3:
                    clicked_enemy = None
                    for ent in entities:
                        if ent.alive and ent.team != player.team:
                            if math.hypot(ent.x - mouse_pos[0], ent.y - mouse_pos[1]) <= ent.radius + 12:
                                clicked_enemy = ent
                                break
                    if clicked_enemy:
                        player.attack_target = clicked_enemy
                        click_markers.append(ClickMarker(clicked_enemy.x, clicked_enemy.y, is_attack=True))
                    else:
                        player.attack_target = None
                        clamped_y = max(140, min(HEIGHT - 140, mouse_pos[1]))
                        player.target_pos = (mouse_pos[0], clamped_y)
                        click_markers.append(ClickMarker(mouse_pos[0], clamped_y, is_attack=False))

                # 키보드 스킬 (스마트키 방식: 마우스 커서 방향으로 즉시 시전)
                if event.type == pygame.KEYDOWN:
                    if event.key == pygame.K_q:
                        player.cast_skill("Q", mouse_pos, projectiles, particles, floating_texts)
                    elif event.key == pygame.K_w:
                        player.cast_skill("W", mouse_pos, projectiles, particles, floating_texts)
                    elif event.key == pygame.K_e:
                        player.cast_skill("E", mouse_pos, projectiles, particles, floating_texts)
                    elif event.key == pygame.K_r:
                        player.cast_skill("R", mouse_pos, projectiles, particles, floating_texts)
                    elif event.key == pygame.K_s:  # S키: 제자리 정지
                        player.target_pos = (player.x, player.y)
                        player.attack_target = None
                    elif event.key == pygame.K_b:  # B키: 상점 아이템 구매 (공격력 업그레이드)
                        if player.gold >= 300:
                            player.gold -= 300
                            player.atk_dmg += 18
                            floating_texts.append(FloatingText(player.x, player.y - 30, "BF 대검 구매! (공격력 +18)", GOLD_COLOR))

        if not game_over:
            game_time += 1
            wave_timer += 1

            # 12초마다 양 팀 미니언 웨이브 생성 (근접 2 + 원거리 1)
            if wave_timer == 1 or wave_timer >= FPS * 12:
                wave_timer = 1
                for i in range(3):
                    is_ranged = (i == 2)
                    offset_x = i * 35
                    entities.append(Minion(240 - offset_x, HEIGHT // 2 + random.randint(-25, 25), "BLUE", is_ranged))
                    entities.append(Minion(WIDTH - 240 + offset_x, HEIGHT // 2 + random.randint(-25, 25), "RED", is_ranged))

            # 엔티티 업데이트
            for ent in entities:
                ent.update(entities, projectiles, particles, floating_texts)

            # 죽은 미니언/포탑 정리 (챔피언은 부활해야 하므로 유지)
            entities = [e for e in entities if e.alive or isinstance(e, Champion)]

            # 적 챔피언 사망 처리
            if not enemy_champ.alive and enemy_champ.respawn_timer == 0:
                enemy_champ.respawn_timer = FPS * 6
            if not player.alive and player.respawn_timer == 0:
                player.respawn_timer = FPS * 6

            # 투사체, 파티클, 텍스트 업데이트
            for p in projectiles:
                p.update(entities, particles, floating_texts, player if p.team == "BLUE" else enemy_champ)
            projectiles = [p for p in projectiles if p.alive]

            for pt in particles:
                pt.update()
            particles = [pt for pt in particles if pt.life > 0]

            for ft in floating_texts:
                ft.update()
            floating_texts = [ft for ft in floating_texts if ft.timer > 0]

            for cm in click_markers:
                cm.update()
            click_markers = [cm for cm in click_markers if cm.timer > 0]

            # 승패 판정 (넥서스 파괴)
            if not red_nexus.alive:
                game_over = "VICTORY! (승리)"
            elif not blue_nexus.alive:
                game_over = "DEFEAT... (패배)"

        # ==========================================
        # 화면 렌더링
        # ==========================================
        screen.fill(BG_COLOR)

        # 중앙 라인 및 부쉬(수풀) 배경 그리기
        pygame.draw.rect(screen, LANE_COLOR, (0, 130, WIDTH, HEIGHT - 260))
        pygame.draw.line(screen, (55, 70, 88), (0, 130), (WIDTH, 130), 4)
        pygame.draw.line(screen, (55, 70, 88), (0, HEIGHT - 130), (WIDTH, HEIGHT - 130), 4)
        pygame.draw.rect(screen, BUSH_COLOR, (WIDTH // 2 - 110, 140, 220, 45), border_radius=12)
        pygame.draw.rect(screen, BUSH_COLOR, (WIDTH // 2 - 110, HEIGHT - 185, 220, 45), border_radius=12)

        for cm in click_markers:
            cm.draw(screen)
        for ent in entities:
            ent.draw(screen)
        for p in projectiles:
            p.draw(screen)
        for pt in particles:
            pt.draw(screen)
        for ft in floating_texts:
            ft.draw(screen)

        draw_hud(screen, player, game_time)

        # 부활 대기 화면 표시
        if not player.alive and not game_over:
            sec = math.ceil(player.respawn_timer / FPS)
            dead_txt = font_lg.render(f"부활 대기 중... {sec}초", True, RED_TEAM)
            screen.blit(dead_txt, (WIDTH // 2 - dead_txt.get_width() // 2, HEIGHT // 2 - 60))

        # 승패 배너 출력
        if game_over:
            overlay = pygame.Surface((WIDTH, HEIGHT), pygame.SRCALPHA)
            overlay.fill((0, 0, 0, 170))
            screen.blit(overlay, (0, 0))
            color = BLUE_TEAM if "VICTORY" in game_over else RED_TEAM
            end_txt = font_lg.render(game_over, True, color)
            sub_txt = font_md.render("R 키를 눌러 다시 시작하세요", True, WHITE)
            screen.blit(end_txt, (WIDTH // 2 - end_txt.get_width() // 2, HEIGHT // 2 - 40))
            screen.blit(sub_txt, (WIDTH // 2 - sub_txt.get_width() // 2, HEIGHT // 2 + 20))

        pygame.display.flip()

if __name__ == "__main__":
    main()
