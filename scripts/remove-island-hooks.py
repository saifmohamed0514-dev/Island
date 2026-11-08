#!/usr/bin/env python3
"""Remove IslandBridge command handlers only, keeping unrelated hooks/settings."""
import argparse,copy,json,os,shlex,stat,tempfile
from pathlib import Path

def is_island(command):
    if not isinstance(command,str):return False
    try: parts=shlex.split(command)
    except ValueError:return False
    return bool(parts) and Path(parts[0]).name == 'IslandBridge' and '--directory' in parts

def remove_island_hooks(data):
    result=copy.deepcopy(data);count=0
    if not isinstance(result,dict) or not isinstance(result.get('hooks'),dict):return result,0
    for event,groups in list(result['hooks'].items()):
        if not isinstance(groups,list):continue
        kept=[]
        for group in groups:
            if not isinstance(group,dict):kept.append(group);continue
            if is_island(group.get('command')):count+=1;continue
            if isinstance(group.get('hooks'),list):
                handlers=[]
                for handler in group['hooks']:
                    if isinstance(handler,dict) and is_island(handler.get('command')):count+=1
                    else:handlers.append(handler)
                if len(handlers)!=len(group['hooks']):
                    group['hooks']=handlers
                    if not handlers:continue
            kept.append(group)
        if kept:result['hooks'][event]=kept
        else:del result['hooks'][event]
    return result,count

if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('paths',nargs='+',type=Path);parser.add_argument('--apply',action='store_true');parser.add_argument('--backup-dir',type=Path);args=parser.parse_args()
    if args.apply and not args.backup_dir:parser.error('--apply requires --backup-dir')
    if args.apply:args.backup_dir.mkdir(parents=True,exist_ok=True);args.backup_dir.chmod(0o700)
    for index,path in enumerate(args.paths):
        if not path.exists():continue
        original=path.read_bytes();data=json.loads(original);clean,count=remove_island_hooks(data)
        print(f'{path.name}: {count} Island handlers'+(' removed' if args.apply else ' found'))
        if not count or not args.apply:continue
        backup=args.backup_dir/f'{index}-{path.parent.name}-{path.name}';backup.write_bytes(original);backup.chmod(0o600)
        if clean == {'hooks':{}}:path.unlink();continue
        with tempfile.NamedTemporaryFile(mode='w',dir=path.parent,delete=False) as temp:
            json.dump(clean,temp,indent=2);temp.write('\n');os.chmod(temp.name,stat.S_IMODE(path.stat().st_mode));temp.flush();os.fsync(temp.fileno())
        os.replace(temp.name,path)
