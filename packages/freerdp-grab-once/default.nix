# キーボードを掴むのを、SDL_Grab のホットキーを押した直後のショートカット一回だけにする FreeRDP。
# マウスがウィンドウに入っても掴まず、ホットキーのあとに押したキーがすべて離されたら放す。
# 理由と外す条件は docs/architecture/windows-vm.md。
{ freerdp }:

freerdp.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [ ./grab-once.patch ];
})
