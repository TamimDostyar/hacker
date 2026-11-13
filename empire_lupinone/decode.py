import base58;open('arsene_key','wb').write(base58.b58decode(open('.mysecret.txt').read().strip()))
