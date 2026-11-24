# KeepStrong — HMA-OSS config merger (POSIX awk; run via busybox awk on-device).
#
# Merges a managed blacklist template + scope entries into an EXISTING HMA-OSS
# config.json (org.frknkrc44.hma_oss), preserving configVersion, the user's own
# templates, and every other scope entry and its settings. HMA writes compact
# single-line JSON, which this parses brace-aware (string/escape/depth tracked).
#
# Inputs (all files; names via -v):
#   cfg    = path to existing config.json  (required, must be a valid object)
#   hide   = path to hide-list  (one package per line -> template appList)
#   tgt    = path to target-list (one package per line -> scope entries)
#   tname  = managed template name (default "KeepStrong")
# Output: merged compact JSON on stdout. On any parse problem it prints nothing
# and exits 2, so the caller leaves the original file untouched.

function fail(msg){ print "ERR " msg > "/dev/stderr"; exit 2 }

# --- whitespace + value scanning over an arbitrary string -------------------
function skip_ws(str,i){ while(i<=length(str)){ c=substr(str,i,1); if(c==" "||c=="\t"||c=="\n"||c=="\r") i++; else break } return i }
# Return index just PAST the JSON value that starts at i (string/object/array/scalar).
function val_end(str,i,   c,depth,instr,esc){
  i=skip_ws(str,i); c=substr(str,i,1)
  if(c=="\""){ i++; esc=0
    while(i<=length(str)){ c=substr(str,i,1)
      if(esc) esc=0; else if(c=="\\") esc=1; else if(c=="\"") return i+1
      i++ }
    fail("unterminated string") }
  if(c=="{"||c=="["){ depth=0; instr=0; esc=0
    while(i<=length(str)){ c=substr(str,i,1)
      if(instr){ if(esc) esc=0; else if(c=="\\") esc=1; else if(c=="\"") instr=0 }
      else { if(c=="\"") instr=1; else if(c=="{"||c=="[") depth++; else if(c=="}"||c=="]"){ depth--; if(depth==0) return i+1 } }
      i++ }
    fail("unbalanced brackets") }
  while(i<=length(str)){ c=substr(str,i,1); if(c==","||c=="}"||c=="]") return i; i++ }
  return i
}
function dequote(s){ if(substr(s,1,1)=="\"") return substr(s,2,length(s)-2); return s }

# Parse an object substring into ordered keys[1..n]/vals[1..n]. Returns n.
function parse_obj(str, keys, vals,   i,n,ks,ke,vs,ve,c){
  n=0; i=skip_ws(str,1)
  if(substr(str,i,1)!="{") fail("not an object"); i++
  i=skip_ws(str,i)
  if(substr(str,i,1)=="}") return 0
  while(1){
    i=skip_ws(str,i)
    ks=i; ke=val_end(str,i); if(substr(str,ks,1)!="\"") fail("key not string")
    i=skip_ws(str,ke); if(substr(str,i,1)!=":") fail("missing colon"); i++
    i=skip_ws(str,i); vs=i; ve=val_end(str,i)
    n++; keys[n]=dequote(substr(str,ks,ke-ks)); vals[n]=substr(str,vs,ve-vs)
    i=skip_ws(str,ve); c=substr(str,i,1)
    if(c==","){ i++; continue }
    if(c=="}") break
    fail("bad object sep")
  }
  return n
}

# JSON-encode a package list file into ["a","b",...]; "[]" when empty/missing.
function arr_from_file(path,   line,out,first){
  out="["; first=1
  while((getline line < path) > 0){
    gsub(/[ \t\r]/,"",line); if(line=="" || substr(line,1,1)=="#") continue
    if(!first) out=out","; out=out "\"" line "\""; first=0
  }
  close(path); return out "]"
}

# Does a compact JSON array substring already contain "val" as a string element?
function arr_has(arrstr,val){ return index(arrstr, "\"" val "\"") > 0 }
# Insert "val" at the front of a compact JSON array substring.
function arr_prepend(arrstr,val){
  if(arrstr=="[]" || arrstr=="[ ]") return "[\"" val "\"]"
  return "[\"" val "\"," substr(arrstr,2)
}

BEGIN{
  if(tname=="") tname="KeepStrong"

  # Read the whole config into S.
  S=""; while((getline line < cfg) > 0) S=S line
  close(cfg)
  if(S=="") fail("empty config")

  # Top-level object.
  tn=parse_obj(S, tkeys, tvals)
  if(tn==0) fail("empty top object")

  # Locate templates + scope; default the scalar settings if missing.
  ti=0; si=0
  for(k=1;k<=tn;k++){ if(tkeys[k]=="templates") ti=k; else if(tkeys[k]=="scope") si=k }

  # --- rebuild templates: keep all, overwrite ours ---
  tmplBody = (ti? tvals[ti] : "{}")
  mn=parse_obj(tmplBody, mk, mv)
  ourTmpl="{\"isWhitelist\":false,\"appList\":" arr_from_file(hide) "}"
  outT="{"; first=1
  for(k=1;k<=mn;k++){ if(mk[k]==tname) continue
    if(!first) outT=outT","; outT=outT "\"" mk[k] "\":" mv[k]; first=0 }
  if(!first) outT=outT","; outT=outT "\"" tname "\":" ourTmpl
  outT=outT "}"

  # --- rebuild scope: keep all, ensure each target applies our template ---
  scopeBody = (si? tvals[si] : "{}")
  sn=parse_obj(scopeBody, sk, sv)
  # existing entries into an assoc for lookup/update
  for(k=1;k<=sn;k++) existing[sk[k]]=sv[k]

  # mark targets
  nt=0
  while((getline line < tgt) > 0){ gsub(/[ \t\r]/,"",line); if(line=="" || substr(line,1,1)=="#") continue; nt++; targets[nt]=line }
  close(tgt)

  # update existing targets' applyTemplates; collect order
  for(k=1;k<=sn;k++){
    body=sv[k]; istarget=0
    for(j=1;j<=nt;j++) if(targets[j]==sk[k]) istarget=1
    if(istarget){
      an=parse_obj(body, ak, av); found=0; rebuilt="{"; f2=1
      for(x=1;x<=an;x++){
        val=av[x]
        if(ak[x]=="applyTemplates"){ found=1; if(!arr_has(val,tname)) val=arr_prepend(val,tname) }
        if(!f2) rebuilt=rebuilt","; rebuilt=rebuilt "\"" ak[x] "\":" val; f2=0
      }
      if(!found){ if(!f2) rebuilt=rebuilt","; rebuilt=rebuilt "\"applyTemplates\":[\"" tname "\"]" }
      rebuilt=rebuilt "}"
      existing[sk[k]]=rebuilt
    }
  }
  # add missing targets with a default AppConfig applying our template
  for(j=1;j<=nt;j++){
    if(!(targets[j] in existing)){
      existing[targets[j]]="{\"useWhitelist\":false,\"excludeSystemApps\":true,\"applyTemplates\":[\"" tname "\"],\"extraAppList\":[]}"
      sn++; sk[sn]=targets[j]
    }
  }
  outS="{"; first=1
  for(k=1;k<=sn;k++){ if(!first) outS=outS","; outS=outS "\"" sk[k] "\":" existing[sk[k]]; first=0 }
  outS=outS "}"

  # --- reassemble top-level object, preserving everything else ---
  out="{"; first=1; haveT=0; haveS=0
  for(k=1;k<=tn;k++){
    v=tvals[k]
    if(tkeys[k]=="templates"){ v=outT; haveT=1 }
    else if(tkeys[k]=="scope"){ v=outS; haveS=1 }
    if(!first) out=out","; out=out "\"" tkeys[k] "\":" v; first=0
  }
  if(!haveT){ out=out ",\"templates\":" outT }
  if(!haveS){ out=out ",\"scope\":" outS }
  out=out "}"
  print out
}
