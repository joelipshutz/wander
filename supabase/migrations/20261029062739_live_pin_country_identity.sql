begin;

-- REC-666: code/name country aliases must not split one physical place into a
-- saved Totem and a Featured dot. This is presentation identity only: no place,
-- activity, save, or permission rows are rewritten.
-- ISO alpha-2/alpha-3 and English country-name aliases follow the existing
-- iOS CountryCanonicalizer (Foundation en_US_POSIX region names). Unrecognized
-- values keep their normalized spelling; blank or conflicting countries are
-- not treated as wildcards. Stored provider IDs remain opaque/case-sensitive.
create function app.live_pin_country_key(input_country text)
returns text language sql stable security invoker
set search_path = pg_catalog, extensions
as $country$
  select coalesce(
    aliases ->> regexp_replace(normalized, '[^a-z0-9]', '', 'g'),
    normalized
  )
  from (select btrim(regexp_replace(lower(extensions.unaccent(coalesce(input_country,''))),
    '[^a-z0-9]+',' ','g')) as normalized) country
  cross join (select $aliases${"abw":"aruba","ac":"ascension island","ad":"andorra","ae":"united arab emirates","af":"afghanistan","afg":"afghanistan","afghanistan":"afghanistan","africa":"africa","ag":"antigua barbuda","ago":"angola","ai":"anguilla","aia":"anguilla","al":"albania","ala":"aland islands","alandislands":"aland islands","alb":"albania","albania":"albania","algeria":"algeria","am":"armenia","americansamoa":"american samoa","americas":"americas","an":"curacao","and":"andorra","andorra":"andorra","angola":"angola","anguilla":"anguilla","ant":"curacao","antarctica":"antarctica","antiguabarbuda":"antigua barbuda","ao":"angola","aq":"antarctica","ar":"argentina","are":"united arab emirates","arg":"argentina","argentina":"argentina","arm":"armenia","armenia":"armenia","aruba":"aruba","as":"american samoa","asc":"ascension island","ascensionisland":"ascension island","asia":"asia","asm":"american samoa","at":"austria","ata":"antarctica","atf":"french southern territories","atg":"antigua barbuda","au":"australia","aus":"australia","australasia":"australasia","australia":"australia","austria":"austria","aut":"austria","aw":"aruba","ax":"aland islands","az":"azerbaijan","aze":"azerbaijan","azerbaijan":"azerbaijan","ba":"bosnia herzegovina","bahamas":"bahamas","bahrain":"bahrain","bangladesh":"bangladesh","barbados":"barbados","bb":"barbados","bd":"bangladesh","bdi":"burundi","be":"belgium","bel":"belgium","belarus":"belarus","belgium":"belgium","belize":"belize","ben":"benin","benin":"benin","bermuda":"bermuda","bes":"caribbean netherlands","bf":"burkina faso","bfa":"burkina faso","bg":"bulgaria","bgd":"bangladesh","bgr":"bulgaria","bh":"bahrain","bhr":"bahrain","bhs":"bahamas","bhutan":"bhutan","bi":"burundi","bih":"bosnia herzegovina","bj":"benin","bl":"st barthelemy","blm":"st barthelemy","blr":"belarus","blz":"belize","bm":"bermuda","bmu":"bermuda","bn":"brunei","bo":"bolivia","bol":"bolivia","bolivia":"bolivia","bosniaherzegovina":"bosnia herzegovina","botswana":"botswana","bouvetisland":"bouvet island","bq":"caribbean netherlands","br":"brazil","bra":"brazil","brazil":"brazil","brb":"barbados","britishvirginislands":"british virgin islands","brn":"brunei","brunei":"brunei","bs":"bahamas","bt":"bhutan","btn":"bhutan","bu":"myanmar burma","bulgaria":"bulgaria","bur":"myanmar burma","burkinafaso":"burkina faso","burundi":"burundi","bv":"bouvet island","bvt":"bouvet island","bw":"botswana","bwa":"botswana","by":"belarus","bz":"belize","ca":"canada","caf":"central african republic","cambodia":"cambodia","cameroon":"cameroon","can":"canada","canada":"canada","canaryislands":"canary islands","capeverde":"cape verde","caribbean":"caribbean","caribbeannetherlands":"caribbean netherlands","caymanislands":"cayman islands","cc":"cocos keeling islands","cck":"cocos keeling islands","cd":"congo kinshasa","centralafricanrepublic":"central african republic","centralamerica":"central america","centralasia":"central asia","ceutamelilla":"ceuta melilla","cf":"central african republic","cg":"congo brazzaville","ch":"switzerland","chad":"chad","chagosarchipelago":"chagos archipelago","che":"switzerland","chile":"chile","chinamainland":"china mainland","chl":"chile","chn":"china mainland","christmasisland":"christmas island","ci":"cote d ivoire","civ":"cote d ivoire","ck":"cook islands","cl":"chile","clippertonisland":"clipperton island","cm":"cameroon","cmr":"cameroon","cn":"china mainland","co":"colombia","cocoskeelingislands":"cocos keeling islands","cod":"congo kinshasa","cog":"congo brazzaville","cok":"cook islands","col":"colombia","colombia":"colombia","com":"comoros","comoros":"comoros","congobrazzaville":"congo brazzaville","congokinshasa":"congo kinshasa","cookislands":"cook islands","costarica":"costa rica","cotedivoire":"cote d ivoire","cp":"clipperton island","cpt":"clipperton island","cpv":"cape verde","cq":"sark","cr":"costa rica","cri":"costa rica","croatia":"croatia","crq":"sark","cs":"serbia","cu":"cuba","cub":"cuba","cuba":"cuba","curacao":"curacao","cuw":"curacao","cv":"cape verde","cw":"curacao","cx":"christmas island","cxr":"christmas island","cy":"cyprus","cym":"cayman islands","cyp":"cyprus","cyprus":"cyprus","cz":"czechia","cze":"czechia","czechia":"czechia","dd":"germany","de":"germany","denmark":"denmark","deu":"germany","dg":"diego garcia","dga":"diego garcia","diegogarcia":"diego garcia","dj":"djibouti","dji":"djibouti","djibouti":"djibouti","dk":"denmark","dm":"dominica","dma":"dominica","dnk":"denmark","do":"dominican republic","dom":"dominican republic","dominica":"dominica","dominicanrepublic":"dominican republic","dy":"benin","dz":"algeria","dza":"algeria","ea":"ceuta melilla","easternafrica":"eastern africa","easternasia":"eastern asia","easterneurope":"eastern europe","ec":"ecuador","ecu":"ecuador","ecuador":"ecuador","ee":"estonia","eg":"egypt","egy":"egypt","egypt":"egypt","eh":"western sahara","elsalvador":"el salvador","equatorialguinea":"equatorial guinea","er":"eritrea","eri":"eritrea","eritrea":"eritrea","es":"spain","esh":"western sahara","esp":"spain","est":"estonia","estonia":"estonia","eswatini":"eswatini","et":"ethiopia","eth":"ethiopia","ethiopia":"ethiopia","eu":"european union","europe":"europe","europeanunion":"european union","eurozone":"eurozone","ez":"eurozone","falklandislands":"falkland islands","faroeislands":"faroe islands","fi":"finland","fiji":"fiji","fin":"finland","finland":"finland","fj":"fiji","fji":"fiji","fk":"falkland islands","flk":"falkland islands","fm":"micronesia","fo":"faroe islands","fr":"france","fra":"france","france":"france","frenchguiana":"french guiana","frenchpolynesia":"french polynesia","frenchsouthernterritories":"french southern territories","fro":"faroe islands","fsm":"micronesia","fx":"france","fxx":"france","ga":"gabon","gab":"gabon","gabon":"gabon","gambia":"gambia","gb":"united kingdom","gbr":"united kingdom","gd":"grenada","ge":"georgia","geo":"georgia","georgia":"georgia","germany":"germany","gf":"french guiana","gg":"guernsey","ggy":"guernsey","gh":"ghana","gha":"ghana","ghana":"ghana","gi":"gibraltar","gib":"gibraltar","gibraltar":"gibraltar","gin":"guinea","gl":"greenland","glp":"guadeloupe","gm":"gambia","gmb":"gambia","gn":"guinea","gnb":"guinea bissau","gnq":"equatorial guinea","gp":"guadeloupe","gq":"equatorial guinea","gr":"greece","grc":"greece","grd":"grenada","greece":"greece","greenland":"greenland","grenada":"grenada","grl":"greenland","gs":"so georgia so sandwich isl","gt":"guatemala","gtm":"guatemala","gu":"guam","guadeloupe":"guadeloupe","guam":"guam","guatemala":"guatemala","guernsey":"guernsey","guf":"french guiana","guinea":"guinea","guineabissau":"guinea bissau","gum":"guam","guy":"guyana","guyana":"guyana","gw":"guinea bissau","gy":"guyana","haiti":"haiti","heardmcdonaldislands":"heard mcdonald islands","hk":"hong kong","hkg":"hong kong","hm":"heard mcdonald islands","hmd":"heard mcdonald islands","hn":"honduras","hnd":"honduras","honduras":"honduras","hongkong":"hong kong","hr":"croatia","hrv":"croatia","ht":"haiti","hti":"haiti","hu":"hungary","hun":"hungary","hungary":"hungary","hv":"burkina faso","ic":"canary islands","iceland":"iceland","id":"indonesia","idn":"indonesia","ie":"ireland","il":"israel","im":"isle of man","imn":"isle of man","in":"india","ind":"india","india":"india","indonesia":"indonesia","io":"chagos archipelago","iot":"chagos archipelago","iq":"iraq","ir":"iran","iran":"iran","iraq":"iraq","ireland":"ireland","irl":"ireland","irn":"iran","irq":"iraq","is":"iceland","isl":"iceland","isleofman":"isle of man","isr":"israel","israel":"israel","it":"italy","ita":"italy","italy":"italy","jam":"jamaica","jamaica":"jamaica","japan":"japan","je":"jersey","jersey":"jersey","jey":"jersey","jm":"jamaica","jo":"jordan","jor":"jordan","jordan":"jordan","jp":"japan","jpn":"japan","kaz":"kazakhstan","kazakhstan":"kazakhstan","ke":"kenya","ken":"kenya","kenya":"kenya","kg":"kyrgyzstan","kgz":"kyrgyzstan","kh":"cambodia","khm":"cambodia","ki":"kiribati","kir":"kiribati","kiribati":"kiribati","km":"comoros","kn":"st kitts nevis","kna":"st kitts nevis","kor":"south korea","kosovo":"kosovo","kp":"north korea","kr":"south korea","kuwait":"kuwait","kw":"kuwait","kwt":"kuwait","ky":"cayman islands","kyrgyzstan":"kyrgyzstan","kz":"kazakhstan","la":"laos","lao":"laos","laos":"laos","latinamerica":"latin america","latvia":"latvia","lb":"lebanon","lbn":"lebanon","lbr":"liberia","lby":"libya","lc":"st lucia","lca":"st lucia","lebanon":"lebanon","lesotho":"lesotho","li":"liechtenstein","liberia":"liberia","libya":"libya","lie":"liechtenstein","liechtenstein":"liechtenstein","lithuania":"lithuania","lk":"sri lanka","lka":"sri lanka","lr":"liberia","ls":"lesotho","lso":"lesotho","lt":"lithuania","ltu":"lithuania","lu":"luxembourg","lux":"luxembourg","luxembourg":"luxembourg","lv":"latvia","lva":"latvia","ly":"libya","ma":"morocco","mac":"macao","macao":"macao","madagascar":"madagascar","maf":"st martin","malawi":"malawi","malaysia":"malaysia","maldives":"maldives","mali":"mali","malta":"malta","mar":"morocco","marshallislands":"marshall islands","martinique":"martinique","mauritania":"mauritania","mauritius":"mauritius","mayotte":"mayotte","mc":"monaco","mco":"monaco","md":"moldova","mda":"moldova","mdg":"madagascar","mdv":"maldives","me":"montenegro","melanesia":"melanesia","mex":"mexico","mexico":"mexico","mf":"st martin","mg":"madagascar","mh":"marshall islands","mhl":"marshall islands","micronesia":"micronesia","micronesianregion":"micronesian region","middleafrica":"middle africa","mk":"north macedonia","mkd":"north macedonia","ml":"mali","mli":"mali","mlt":"malta","mm":"myanmar burma","mmr":"myanmar burma","mn":"mongolia","mne":"montenegro","mng":"mongolia","mnp":"northern mariana islands","mo":"macao","moldova":"moldova","monaco":"monaco","mongolia":"mongolia","montenegro":"montenegro","montserrat":"montserrat","morocco":"morocco","moz":"mozambique","mozambique":"mozambique","mp":"northern mariana islands","mq":"martinique","mr":"mauritania","mrt":"mauritania","ms":"montserrat","msr":"montserrat","mt":"malta","mtq":"martinique","mu":"mauritius","mus":"mauritius","mv":"maldives","mw":"malawi","mwi":"malawi","mx":"mexico","my":"malaysia","myanmarburma":"myanmar burma","mys":"malaysia","myt":"mayotte","mz":"mozambique","na":"namibia","nam":"namibia","namibia":"namibia","nauru":"nauru","nc":"new caledonia","ncl":"new caledonia","ne":"niger","nepal":"nepal","ner":"niger","netherlands":"netherlands","newcaledonia":"new caledonia","newzealand":"new zealand","nf":"norfolk island","nfk":"norfolk island","ng":"nigeria","nga":"nigeria","nh":"vanuatu","ni":"nicaragua","nic":"nicaragua","nicaragua":"nicaragua","niger":"niger","nigeria":"nigeria","niu":"niue","niue":"niue","nl":"netherlands","nld":"netherlands","no":"norway","nor":"norway","norfolkisland":"norfolk island","northamerica":"north america","northernafrica":"northern africa","northernamerica":"northern america","northerneurope":"northern europe","northernmarianaislands":"northern mariana islands","northkorea":"north korea","northmacedonia":"north macedonia","norway":"norway","np":"nepal","npl":"nepal","nr":"nauru","nru":"nauru","nu":"niue","nz":"new zealand","nzl":"new zealand","oceania":"oceania","om":"oman","oman":"oman","omn":"oman","outlyingoceania":"outlying oceania","pa":"panama","pak":"pakistan","pakistan":"pakistan","palau":"palau","palestinianterritories":"palestinian territories","pan":"panama","panama":"panama","papuanewguinea":"papua new guinea","paraguay":"paraguay","pcn":"pitcairn islands","pe":"peru","per":"peru","peru":"peru","pf":"french polynesia","pg":"papua new guinea","ph":"philippines","philippines":"philippines","phl":"philippines","pitcairnislands":"pitcairn islands","pk":"pakistan","pl":"poland","plw":"palau","pm":"st pierre miquelon","pn":"pitcairn islands","png":"papua new guinea","pol":"poland","poland":"poland","polynesia":"polynesia","portugal":"portugal","pr":"puerto rico","pri":"puerto rico","prk":"north korea","prt":"portugal","pry":"paraguay","ps":"palestinian territories","pse":"palestinian territories","pt":"portugal","puertorico":"puerto rico","pw":"palau","py":"paraguay","pyf":"french polynesia","qa":"qatar","qat":"qatar","qatar":"qatar","qo":"outlying oceania","re":"reunion","reu":"reunion","reunion":"reunion","rh":"zimbabwe","ro":"romania","rom":"romania","romania":"romania","rou":"romania","rs":"serbia","ru":"russia","rus":"russia","russia":"russia","rw":"rwanda","rwa":"rwanda","rwanda":"rwanda","sa":"saudi arabia","samoa":"samoa","sanmarino":"san marino","saotomeprincipe":"sao tome principe","sark":"sark","sau":"saudi arabia","saudiarabia":"saudi arabia","sb":"solomon islands","sc":"seychelles","scg":"serbia","sd":"sudan","sdn":"sudan","se":"sweden","sen":"senegal","senegal":"senegal","serbia":"serbia","seychelles":"seychelles","sg":"singapore","sgp":"singapore","sgs":"so georgia so sandwich isl","sh":"st helena","shn":"st helena","si":"slovenia","sierraleone":"sierra leone","singapore":"singapore","sintmaarten":"sint maarten","sj":"svalbard jan mayen","sjm":"svalbard jan mayen","sk":"slovakia","sl":"sierra leone","slb":"solomon islands","sle":"sierra leone","slovakia":"slovakia","slovenia":"slovenia","slv":"el salvador","sm":"san marino","smr":"san marino","sn":"senegal","so":"somalia","sogeorgiasosandwichisl":"so georgia so sandwich isl","solomonislands":"solomon islands","som":"somalia","somalia":"somalia","southafrica":"south africa","southamerica":"south america","southeastasia":"southeast asia","southernafrica":"southern africa","southernasia":"southern asia","southerneurope":"southern europe","southkorea":"south korea","southsudan":"south sudan","spain":"spain","spm":"st pierre miquelon","sr":"suriname","srb":"serbia","srilanka":"sri lanka","ss":"south sudan","ssd":"south sudan","st":"sao tome principe","stbarthelemy":"st barthelemy","sthelena":"st helena","stkittsnevis":"st kitts nevis","stlucia":"st lucia","stmartin":"st martin","stp":"sao tome principe","stpierremiquelon":"st pierre miquelon","stvincentgrenadines":"st vincent grenadines","su":"russia","subsaharanafrica":"sub saharan africa","sudan":"sudan","sun":"russia","sur":"suriname","suriname":"suriname","sv":"el salvador","svalbardjanmayen":"svalbard jan mayen","svk":"slovakia","svn":"slovenia","swe":"sweden","sweden":"sweden","switzerland":"switzerland","swz":"eswatini","sx":"sint maarten","sxm":"sint maarten","sy":"syria","syc":"seychelles","syr":"syria","syria":"syria","sz":"eswatini","ta":"tristan da cunha","taa":"tristan da cunha","taiwan":"taiwan","tajikistan":"tajikistan","tanzania":"tanzania","tc":"turks caicos islands","tca":"turks caicos islands","tcd":"chad","td":"chad","tf":"french southern territories","tg":"togo","tgo":"togo","th":"thailand","tha":"thailand","thailand":"thailand","timorleste":"timor leste","tj":"tajikistan","tjk":"tajikistan","tk":"tokelau","tkl":"tokelau","tkm":"turkmenistan","tl":"timor leste","tls":"timor leste","tm":"turkmenistan","tmp":"timor leste","tn":"tunisia","to":"tonga","togo":"togo","tokelau":"tokelau","ton":"tonga","tonga":"tonga","tp":"timor leste","tr":"turkiye","trinidadtobago":"trinidad tobago","tristandacunha":"tristan da cunha","tt":"trinidad tobago","tto":"trinidad tobago","tun":"tunisia","tunisia":"tunisia","tur":"turkiye","turkiye":"turkiye","turkmenistan":"turkmenistan","turkscaicosislands":"turks caicos islands","tuv":"tuvalu","tuvalu":"tuvalu","tv":"tuvalu","tw":"taiwan","twn":"taiwan","tz":"tanzania","tza":"tanzania","ua":"ukraine","ug":"uganda","uga":"uganda","uganda":"uganda","uk":"united kingdom","ukr":"ukraine","ukraine":"ukraine","um":"u s outlying islands","umi":"u s outlying islands","un":"united nations","unitedarabemirates":"united arab emirates","unitedkingdom":"united kingdom","unitednations":"united nations","unitedstates":"united states","uruguay":"uruguay","ury":"uruguay","us":"united states","usa":"united states","usoutlyingislands":"u s outlying islands","usvirginislands":"u s virgin islands","uy":"uruguay","uz":"uzbekistan","uzb":"uzbekistan","uzbekistan":"uzbekistan","va":"vatican city","vanuatu":"vanuatu","vat":"vatican city","vaticancity":"vatican city","vc":"st vincent grenadines","vct":"st vincent grenadines","vd":"vietnam","ve":"venezuela","ven":"venezuela","venezuela":"venezuela","vg":"british virgin islands","vgb":"british virgin islands","vi":"u s virgin islands","vietnam":"vietnam","vir":"u s virgin islands","vn":"vietnam","vnm":"vietnam","vu":"vanuatu","vut":"vanuatu","wallisfutuna":"wallis futuna","westernafrica":"western africa","westernasia":"western asia","westerneurope":"western europe","westernsahara":"western sahara","wf":"wallis futuna","wlf":"wallis futuna","world":"world","ws":"samoa","wsm":"samoa","xea":"ceuta melilla","xic":"canary islands","xk":"kosovo","xkk":"kosovo","yd":"yemen","ye":"yemen","yem":"yemen","yemen":"yemen","ymd":"yemen","yt":"mayotte","yu":"serbia","yug":"serbia","za":"south africa","zaf":"south africa","zambia":"zambia","zar":"congo kinshasa","zimbabwe":"zimbabwe","zm":"zambia","zmb":"zambia","zr":"congo kinshasa","zw":"zimbabwe","zwe":"zimbabwe"}$aliases$::jsonb as aliases) known;
$country$;
revoke all on function app.live_pin_country_key(text) from public, anon, authenticated;
comment on function app.live_pin_country_key(text) is
  'Internal bounded ISO/English country identity normalization for Live pins; no row access or authorization decisions.';

-- Restates the exact RPC from 20261028063718; only country-key normalization
-- changes. SECURITY DEFINER, STABLE, pinned search_path, scalar JSON ABI, bounded
-- scope, caller identity, grants and every authorization predicate are retained.
-- REC-657: complete current pin evidence for a bounded set of already-visible
-- canonical-place seeds. No event-time, Feed page, or viewport row limit applies.
-- This returns only authorized owner IDs and Boolean facets, never place/actor
-- content, event IDs, notes, photos, coordinates, or unreadable list identifiers.
-- SECURITY DEFINER is deliberate: feed_events, Wanna records, deletion receipts,
-- and private-list companion provenance are not directly client-readable.
-- The caller is exclusively app.current_user_id(); all per-source authorization
-- gates are restated below instead of trusting RLS inside a definer function.
-- Reviewed helper history: current_user_id (20260814090000); can_read_user_place,
-- is_blocked/is_mutual (20260602131500); can_read_place_list (20260628112000,
-- 20260810230002, 20260810233134); can_read_activity_event (20260810155601,
-- 20260810232001, 20260811044537, 20260916171502, 20260924031627);
-- can_read_visit_source/private_list_companion_origins (20260923222333);
-- repeat/historical Wannas (20260916171502, 20260916193623, 20260918062209);
-- list-detail resolution (20260818195517). None of those contracts is changed.
-- Guarded canonical alias expansion is copied from live_place_activity
-- (20261023192300): UUID references require nearby corroboration, while opaque
-- provider IDs remain case-sensitive within normalized provider namespaces.
create or replace function public.live_map_pin_states(input_place_ids uuid[])
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, app, extensions
as $$
declare
  viewer_id text := app.current_user_id();
  query_place_ids uuid[];
begin
  if viewer_id is null or not exists (
    select 1 from public.profiles viewer where viewer.id=viewer_id and viewer.deleted_at is null
  ) then raise exception 'not_authenticated' using errcode='28000'; end if;
  if input_place_ids is null or cardinality(input_place_ids) not between 1 and 200
    or coalesce(array_ndims(input_place_ids),1) <> 1
    or exists(select 1 from unnest(input_place_ids) requested(id) where requested.id is null)
  then raise exception 'Invalid Live pin state scope' using errcode='22023'; end if;
  select array_agg(requested.id order by requested.id) into query_place_ids
    from (select distinct unnest(input_place_ids) as id) requested;

  return (
    with recursive
    requested(id) as (select unnest(query_place_ids)),
    matching_places(seed_id, id) as (
      select requested.id, seed.id from requested
      join public.places seed on seed.id=requested.id
      union
      select matched.seed_id, target.id
      from matching_places matched
      join public.places anchor on anchor.id=matched.id
      cross join lateral (
        -- Each arm uses the PK, provider/reference expression index, or existing
        -- geog GiST. Normalize text only for these scoped candidate pairs.
        select candidate.id, 'uuid'::text as evidence from public.places candidate
        where candidate.id=case when btrim(anchor.source_provider_place_id) ~*
          '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
          then btrim(anchor.source_provider_place_id)::uuid end
        union
        select candidate.id, 'uuid' from public.places candidate
        where btrim(candidate.source_provider_place_id) ~*
          '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
          and lower(btrim(candidate.source_provider_place_id))=anchor.id::text
        union
        select candidate.id, case when btrim(anchor.source_provider_place_id) ~*
          '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
          then 'uuid' else 'provider' end from public.places candidate
        where candidate.source_provider_place_id is not null
          and nullif(btrim(anchor.source_provider_place_id),'') is not null
          and nullif(btrim(anchor.source_provider),'') is not null
          -- Provider namespaces are case insensitive; opaque IDs are not.
          -- Shared UUID-valued tokens remain weak reference evidence and must
          -- pass the same nearby/name-or-address checks below.
          and btrim(candidate.source_provider_place_id)=btrim(anchor.source_provider_place_id)
          and lower(btrim(candidate.source_provider))=lower(btrim(anchor.source_provider))
        union
        select candidate.id, 'address' from public.places candidate
        where st_dwithin(candidate.geog,anchor.geog,100)
      ) edge
      join public.places target on target.id=edge.id
      cross join lateral (
        select btrim(regexp_replace(lower(extensions.unaccent(coalesce(anchor.canonical_name,''))), '[^a-z0-9]+',' ','g')) as name_key,
          btrim(regexp_replace(lower(extensions.unaccent(coalesce(anchor.locality,''))), '[^a-z0-9]+',' ','g')) as locality_key,
          btrim(regexp_replace(lower(extensions.unaccent(coalesce(anchor.region,''))), '[^a-z0-9]+',' ','g')) as region_key,
          app.live_pin_country_key(anchor.country) as country_key,
          coalesce((select string_agg(coalesce(
            '{"avenue":"ave","boulevard":"blvd","circle":"cir","court":"ct","drive":"dr","highway":"hwy","lane":"ln","parkway":"pkwy","place":"pl","road":"rd","street":"st","terrace":"ter"}'::jsonb ->> token.value,
            token.value), ' ' order by token.ordinality)
            from regexp_split_to_table(btrim(regexp_replace(lower(extensions.unaccent(coalesce(anchor.address,''))), '[^a-z0-9]+',' ','g')), ' +')
              with ordinality token(value,ordinality)), '') as address_key
      ) anchor_key
      cross join lateral (
        select btrim(regexp_replace(lower(extensions.unaccent(coalesce(target.canonical_name,''))), '[^a-z0-9]+',' ','g')) as name_key,
          btrim(regexp_replace(lower(extensions.unaccent(coalesce(target.locality,''))), '[^a-z0-9]+',' ','g')) as locality_key,
          btrim(regexp_replace(lower(extensions.unaccent(coalesce(target.region,''))), '[^a-z0-9]+',' ','g')) as region_key,
          app.live_pin_country_key(target.country) as country_key,
          coalesce((select string_agg(coalesce(
            '{"avenue":"ave","boulevard":"blvd","circle":"cir","court":"ct","drive":"dr","highway":"hwy","lane":"ln","parkway":"pkwy","place":"pl","road":"rd","street":"st","terrace":"ter"}'::jsonb ->> token.value,
            token.value), ' ' order by token.ordinality)
            from regexp_split_to_table(btrim(regexp_replace(lower(extensions.unaccent(coalesce(target.address,''))), '[^a-z0-9]+',' ','g')), ' +')
              with ordinality token(value,ordinality)), '') as address_key
      ) target_key
      where edge.evidence='provider'
        or (st_dwithin(target.geog,anchor.geog,100) and (
          -- Provider UUID references are client supplied. Both directions and
          -- chains need nearby compatible identity evidence, not just a UUID.
          (edge.evidence='uuid' and (
            (anchor_key.name_key<>'' and target_key.name_key=anchor_key.name_key)
            or (anchor_key.address_key<>'' and target_key.address_key=anchor_key.address_key
              and anchor_key.locality_key<>'' and target_key.locality_key=anchor_key.locality_key)))
          or (edge.evidence='address'
            and anchor_key.name_key<>'' and target_key.name_key=anchor_key.name_key
            and anchor_key.address_key<>'' and target_key.address_key=anchor_key.address_key
            and anchor_key.locality_key<>'' and target_key.locality_key=anchor_key.locality_key
            and target_key.region_key=anchor_key.region_key and target_key.country_key=anchor_key.country_key)
        ))
    ),
    visible_parents as materialized (
      select matched.seed_id, saved.id as user_place_id, saved.place_id, saved.user_id as owner_id,
        saved.status, saved.source_type
      from matching_places matched
      join public.user_places saved on saved.place_id=matched.id
      join public.profiles owner on owner.id=saved.user_id
      where saved.deleted_at is null and owner.deleted_at is null
        and (saved.user_id=viewer_id or not coalesce(owner.is_private_profile,false))
        and app.can_read_user_place(viewer_id,saved.user_id,saved.visibility)
    ),
    save_evidence as materialized (
      select parent.seed_id, parent.owner_id,
        -- Existing legacy Been saves were backfilled by the visit trigger.
        -- Parent.status must not resurrect a deleted visit or a list companion.
        exists (
          select 1 from public.place_visits visit
          where visit.user_place_id=parent.user_place_id and visit.deleted_at is null
            and app.can_read_visit_source(viewer_id,visit.id)
        ) as has_been,
        (
          exists (
            select 1 from public.place_wanna_saves wanna
            join public.feed_events event on event.id=wanna.id
            where wanna.user_place_id=parent.user_place_id
              and event.user_place_id=parent.user_place_id and event.place_id=parent.place_id
              and event.actor_user_id=parent.owner_id and event.event_type='place_want_to_go'
              and event.id=app.canonical_activity_id(event.id)
              and app.can_read_activity_event(viewer_id,event.id)
              and not exists(select 1 from app.deleted_place_wannas deleted where deleted.id=wanna.id)
          )
          or exists (
            -- Older original Wanna events may lack the later independent row.
            -- Preserve visible_place_wannas/wannaSaves semantics, including a
            -- surviving historical original; never infer intent from status.
            select 1 from public.feed_events event
            where event.user_place_id=parent.user_place_id and event.place_id=parent.place_id
              and event.actor_user_id=parent.owner_id and event.event_type='place_want_to_go'
              and event.id=app.canonical_activity_id(event.id)
              and app.can_read_activity_event(viewer_id,event.id)
              and not exists(select 1 from public.place_wanna_saves wanna where wanna.id=event.id)
              and not exists(select 1 from app.deleted_place_wannas deleted where deleted.id=event.id)
              and not exists(select 1 from app.private_list_companion_origins companion
                where companion.user_place_id=parent.user_place_id)
          )
          or exists (
            -- Legacy social saves emitted place_saved instead of Wanna. The
            -- Live activity helper classifies that event using parent status.
            -- Require the surviving event and an untouched intent history so
            -- list-retained parents cannot resurrect deleted Wanna/Been state.
            select 1 from public.feed_events event
            where parent.status='wanna_go' and parent.source_type='social_save'
              and event.user_place_id=parent.user_place_id and event.place_id=parent.place_id
              and event.actor_user_id=parent.owner_id and event.event_type='place_saved'
              and event.id=app.canonical_activity_id(event.id)
              and app.can_read_activity_event(viewer_id,event.id)
              and not exists(select 1 from public.place_wanna_saves wanna where wanna.id=event.id)
              and not exists(select 1 from app.deleted_place_wannas deleted
                where deleted.user_place_id=parent.user_place_id)
              and not exists(select 1 from public.place_visits visit
                where visit.user_place_id=parent.user_place_id)
              and not exists(select 1 from app.private_list_companion_origins companion
                where companion.user_place_id=parent.user_place_id)
          )
        ) as has_wanna
      from visible_parents parent
    ),
    owner_facets as (
      select seed_id, owner_id, bool_or(has_been) as has_been, bool_or(has_wanna) as has_wanna
      from save_evidence
      group by seed_id, owner_id
      having bool_or(has_been) or bool_or(has_wanna)
    ),
    list_memberships as (
      select distinct matched.seed_id
      from matching_places matched
      join public.place_list_items item on item.place_id=matched.id
      join public.place_lists list on list.id=item.list_id
      join public.profiles list_owner on list_owner.id=list.owner_user_id
      where item.deleted_at is null and list.deleted_at is null and list_owner.deleted_at is null
        and app.can_read_place_list(list.id,viewer_id)
        and exists (
          -- Match the current readable list-detail contract. A reference must
          -- belong to this exact place, remain active, and be viewer-readable.
          select 1 from public.user_places reference
          join public.profiles reference_owner on reference_owner.id=reference.user_id
          where reference.id in (item.owner_user_place_id,item.source_user_place_id)
            and reference.place_id=item.place_id and reference.deleted_at is null
            and reference_owner.deleted_at is null
            and app.can_read_user_place(viewer_id,reference.user_id,reference.visibility)
        )
    )
    select jsonb_build_object(
      'states',coalesce((
        select jsonb_agg(jsonb_build_object(
          'place_id',requested.id,
          'saves',coalesce((
            select jsonb_agg(jsonb_build_object(
              'owner_id',facet.owner_id,'has_been',facet.has_been,'has_wanna',facet.has_wanna,
              'is_friend',facet.owner_id<>viewer_id and app.is_mutual(viewer_id,facet.owner_id)
            ) order by facet.owner_id)
            from owner_facets facet where facet.seed_id=requested.id
          ),'[]'::jsonb),
          'has_list_membership',exists(select 1 from list_memberships membership where membership.seed_id=requested.id)
        ) order by requested.id)
        from requested
      ),'[]'::jsonb),
      'complete',true,
      'fetched_at',now()
    )
  );
end;
$$;

revoke all on function public.live_map_pin_states(uuid[]) from public, anon;
grant execute on function public.live_map_pin_states(uuid[]) to authenticated;
comment on function public.live_map_pin_states(uuid[]) is
  'Complete current viewer-authorized Been/Wanna facets and readable list membership for at most 200 canonical place seeds. One scalar JSON object with every requested seed; no event window or content payload.';

-- Security posture is part of the client contract, not an incidental default.
do $$
declare procedure record;
begin
  select prosecdef, provolatile, proconfig into procedure
  from pg_proc where oid='public.live_map_pin_states(uuid[])'::regprocedure;
  if not procedure.prosecdef or procedure.provolatile<>'s'
    or not coalesce(procedure.proconfig @> array['search_path=pg_catalog, public, app, extensions'],false)
    or has_function_privilege('anon','public.live_map_pin_states(uuid[])','execute')
    or not has_function_privilege('authenticated','public.live_map_pin_states(uuid[])','execute') then
    raise exception 'Invalid Live pin state RPC security contract';
  end if;
end;
$$;

commit;
