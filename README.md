# GMod Forcefield Whitelist

![License: BSL-1.0](https://img.shields.io/badge/license-BSL--1.0-blue.svg)
![Game: Garry's Mod](https://img.shields.io/badge/game-Garry's%20Mod-orange.svg)

Аддон для Garry's Mod, добавляющий **вайтлист доступа к силовым полям** из мода
[Bendable Combine Forcefield](https://steamcommunity.com/sharedfiles/filedetails/?id=3824144302) (автор — **bol_snaphak**).

Оригинальный мод позволяет игнорировать поле только по командам. Этот аддон расширяет доступ:

- поимённо игрокам;
- редакторам;
- NPC-классам (например, `npc_vj_automaton_trooper` — проходят все боты этого типа).

Работает как независимый аддон-надстройка: файлы оригинального мода не изменяются.

---

## Возможности

- **Меню управления полем** — открывается четырьмя способами:
  - клавиша **E** по полю (эмиттеры не перехватываются — у них остаётся штатное вкл/выкл);
  - пункт **Forcefield Menu** в контекстном меню (C → ПКМ по полю);
  - консольная команда `ffwl_menu`;
  - чат-команда `!ffmenu`.
- **Вайтлист** четырёх типов:
  - игроки (Add Player / Remove Player);
  - команды через родной механизм мода (Add Team / Remove Team);
  - редакторы (Add Editor / Remove Editor) — на выбор роль `admin`, `operator`, `moderator` или своё название;
  - NPC-классы (Add NPC Class / Remove NPC Class).
- **Персональный проход NPC**: вайтлистному NPC в зоне ~170 юнитов от поля временно меняется группа коллизий,
  за 250 юнитов возвращается. Толпа NPC у стены не «открывает» проход — поле пропускает только конкретную
  сущность из списка.
- **Права доступа**: поле редактируют админы, владелец (по CPPI) и держатели ULX-флага `forcefield_edit`
  (XGUI → Groups). Без ULib — обычная проверка `IsAdmin`.

## Как это работает (и почему стабильно)

В оригинальном моде коллизиями поля управляет один серверный хук:

```lua
hook.Add("ShouldCollide", "Forcefield_ShouldCollide", function(ent1, ent2) ...
```

В GMod при нескольких хуках `ShouldCollide` срабатывает первый, кто вернул ответ, и порядок вызова не
гарантирован. Аддон с конкурирующим хуком работает «то да, то нет» — это была главная причина сбоев ранних
версий. Поэтому здесь **своих хуков `ShouldCollide` нет вообще**: аддон оборачивает родной метод поля
`ENT:ShouldCollideWith`. Проверка вайтлиста выполняется до оригинальной логики мода, и конфликты по порядку
вызова невозможны в принципе.

```lua
local originalShouldCollideWith = ENT.ShouldCollideWith
function ENT:ShouldCollideWith(ent)
    if not FFWL.ShouldPass(self, ent) then
        return originalShouldCollideWith(self, ent)
    end
    return false -- вайтлистная сущность проходит свободно
end
```

Вайтлист команд управляется через родные методы мода (`AddTeamToWhitelist` / `RemoveTeamFromWhitelist`),
поэтому он синхронизирован со штатным пунктом контекстного меню «Teams Ignored by the Field».

## Механика прохода NPC

GMod не умеет отключать ИИ-обход одного конкретного препятствия, поэтому:

1. каждые 0.2 секунды таймер находит вайтлистных NPC в зоне ~170 юнитов от поля и даёт им персональный
   «билет» с гистерезисом до 250 юнитов;
2. в поле зрения ботов поле перестаёт считаться препятствием;
3. за пределами зоны (или после смерти NPC) группа коллизий возвращается.

Обход реализован на клиенте — вызовами `ENT:DoCollision` / `ENT:DoMesh`, встроенными в штатный Think поля.

## Установка

1. Установите оригинальный мод с [страницы Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3824144302).
2. Скачайте этот аддон и поместите папку `forcefield_whitelist` в `garrysmod\addons\`.
3. Перезапустите игру. В консоли должна появиться строка `[FFWL] Адаптация под prop_forcefield_field загружена`.

## Кнопки меню

| Кнопка | Что делает |
|---|---|
| Add Player | Добавить игрока в вайтлист |
| Remove Player | Убрать игрока из вайтлиста |
| Add Team | Добавить команду (родной механизм мода) |
| Remove Team | Убрать команду |
| Add Editor | Добавить редактора (роль на выбор) |
| Remove Editor | Убрать редактора |
| Add NPC Class | Добавить класс NPC (например, `npc_vj_automaton_trooper`) |
| Remove NPC Class | Убрать класс NPC |

## Консольные команды

| Команда | Описание |
|---|---|
| `ffwl_menu` | Открыть меню (наведясь на поле) |
| `ffwl_scan` | Список полей на карте с их классами |
| `ffwl_debug` | Полная диагностика: класс, коллизия, владелец, права, всё содержимое вайтлиста |

`ffwl_scan` и `ffwl_debug` доступны админам и держателям ULX-флага `forcefield_edit`.

## Известные ограничения

- Вайтлист хранится на сущности поля: после пересоздания поля или смены карты список пуст.
- При типе поля 2 (блок пуль) трейсы мод блокирует сам, не зная стрелявшего — сквозь поле не летят пули
  даже у вайтлистных.
- NPC-проход — по классу, а не по конкретному боту (индивидуальный список добавляемо по запросу).

## Лицензия

Проект распространяется под **Boost Software License 1.0**.

```
Boost Software License - Version 1.0 - August 17th, 2003

Permission is hereby granted, free of charge, to any person or organization
obtaining a copy of the software and accompanying documentation covered by
this license (the "Software") to use, reproduce, display, distribute,
execute, and transmit the Software, and to prepare derivative works of the
Software, and to permit third-parties to whom the Software is furnished to
do so, all subject to the following:

The copyright notices in the Software and this entire statement, including
the above license grant and this restriction, must be included in all copies
or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
```

## Благодарности

- **bol_snaphak** — оригинальный мод Combine Forcefield с читаемым кодом, который легко расширять.
- Адаптация вайтлиста — распространяется под той же Boost Software License 1.0.
