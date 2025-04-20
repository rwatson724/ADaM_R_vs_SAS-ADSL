/* clear out work directory */
resetline;
proc datasets lib = work nolist memtype = data kill force;
quit;

options validvarname = v7;
libname sdtm 'C:\Users\gonza\OneDrive - datarichconsulting.com\Desktop\GitHub\Beautiful_Minds\Data\SDTM';
libname adam 'C:\Users\gonza\OneDrive - datarichconsulting.com\Desktop\GitHub\Beautiful_Minds\Data\ADaM';
libname cadam 'C:\Users\gonza\OneDrive - datarichconsulting.com\Desktop\GitHub\Beautiful_Minds\Data\ADaM\CDISC' access = readonly;

resetline;
/**************************************************/
/*** BEGIN SECTION TO CREATE THE SHELL DATA SET ***/
/**************************************************/
libname specs 'C:\Users\gonza\OneDrive - datarichconsulting.com\Desktop\GitHub\Beautiful_Minds\adam_define.xlsx';

data adslspec;
   length allvars $2000;
   set specs.'ADSL$'n end = eof;
   retain allvars;
   length dc $200;
   call missing(dc, dn);
   allvars = catx(' ', allvars, variable);
   if eof then call symputx('allvars', allvars);
run;

libname specs clear;

/* OPTION 1 - CREATING SHELL DATA SET */
/* create all numeric variables */
proc transpose data = adslspec out = tspec_n;
   var dn;
   id variable;
   idlabel label;
   where lowcase(type) in ('integer' 'float');
run;

/* create all character variables */
proc transpose data = adslspec out = tspec_c;
   var dc;
   id variable;
   idlabel label;
   where lowcase(type) not in ('integer' 'float');
run;

/* create master shell */
data adslskel;
   retain &allvars;
   set tspec_: (drop = _:);
run;

/* OPTION 2 - CREATING SHELL DATA SET */
data _null_;
   set adslspec end = eof;
   if _n_ = 1 then do;   
      call execute ('data adslskel;');
      call execute ('   attrib');
   end;
   if lowcase(type) not in ('integer' 'float') then __length = cats('$', length, '.');
   else __length = cats(length, '.');
   if not missing(DISPLAY_FORMAT) then __format = catx(' ', 'format =', DISPLAY_FORMAT);
   attrbstmt = catx(' ', VARIABLE, 'label = ', quote(strip(LABEL)), 'length = ', __length, __format);
   call execute (attrbstmt);
   if eof then do;
      call execute('; call missing(of _all_); stop; run;');
   end;
run;
/************************************************/
/*** END SECTION TO CREATE THE SHELL DATA SET ***/
/************************************************/

resetline;
/**********************************************/
/*** BEGIN SECTION TO RETRIEVE ALL THE DATA ***/
/**********************************************/
/* demographic */
data src_dm (drop = __orig:);
   set SDTM.DM (rename = (AGEU = __origageu RACE = __origrace ETHNIC = __origethnic));
   where ARMCD ne 'Scrnfail';
   length AGEU $5 RACE $32 ETHNIC $22 AGEGR1 $5;
   AGEU = strip(__origageu);
   RACE = strip(__origrace);
   ETHNIC = strip(__origethnic);

   if input(SITEID, best.) in (702 706 707 711 714 715 717) then SITEGR1 = '900';
   else SITEGR1 = SITEID;
   TRT01P = ARM;
   if ARM =: 'Placebo' then TRT01PN = 0;
   else if find(ARM, 'Low', 'i') then TRT01PN = 54;
   else if find(ARM, 'High', 'i') then TRT01PN = 81;

   if . < AGE < 65 then AGEGR1 = '<65';
   else if 65 <= AGE <= 80 then AGEGR1 = '65-80';
   else if AGE > 80 then AGEGR1 = '>80';
   if not missing(AGEGR1) then AGEGR1N = whichc(first(AGEGR1), '<', '6', '>');

   if not missing(RACE) then RACEN = whichc(substr(RACE, 1, 2), 'WH', 'BL', 'xx', 'xx', 'xx', 'AM', 'AS');

   if not missing(ARMCD) then ITTFL = 'Y';
   else ITTFL = 'N';

   format RFENDT date9.;
   if not missing(RFENDTC) then RFENDT = input(RFENDTC, e8601da.);
run;

/* disposition */
data src_ds (keep = USUBJID VISNUMEN DC: DISCONFL DSRAEFL);
   set SDTM.DS;
   by USUBJID;
   retain VISNUMEN DCDECOD DCREASCD;
   length DCDECOD $27 DCREASCD $18;
   if first.USUBJID then call missing(VISNUMEN, DCDECOD, DCREASCD);

   if DSCAT = 'DISPOSITION EVENT' then do;
      if VISITNUM ^= 13 then VISNUMEN = VISITNUM;
      else VISNUMEN = 12;

      DCDECOD = DSDECOD;
      if DSDECOD not in: ('STUDY' 'WITH' 'SCRE' 'LOST') then DCREASCD = tranwrd(propcase(DSDECOD), ' Of ', ' of ');
      else if DSDECOD =: 'STUDY' then DCREASCD = 'Sponsor Decision';
      else if DSDECOD =: 'WITH' then DCREASCD = 'Withdrew Consent';
      else if DSDECOD =: 'SCRE' then DCREASCD = 'I/E Not Met';
      else if DSDECOD =: 'LOST' then DCREASCD = 'Lost to Follow-up';

      if DSTERM = 'PROTOCOL ENTRY CRITERIA NOT MET' then DCREASCD = 'I/E Not Met';
   end;
   if last.USUBJID;
   if DCDECOD ^= 'COMPLETED' then DISCONFL = 'Y';
   if DCDECOD = 'ADVERSE EVENT' then DSRAEFL = 'Y';
run;

/* baseline vitals */
proc sort data = SDTM.VS out = vs;
   by USUBJID VSTESTCD;
   where (VSTESTCD = 'HEIGHT' and VISITNUM = 1) or (VSTESTCD = 'WEIGHT' and VISITNUM = 3);
run;

proc transpose data = vs
               out = src_vs (drop = _:)
               suffix = BL;
   by USUBJID;
   id VSTESTCD;
   var VSSTRESN;
run;

/* treatment start and subject visit */
data src_sv (keep = USUBJID VISIT1DT TRTSDT __vis:);
   set SDTM.SV;
   by USUBJID;
   format VISIT1DT TRTSDT __vis4dt __vis8dt __vis10dt __vis12dt date9.;
   retain VISIT1DT TRTSDT __vis4dt __vis8dt __vis10dt __vis12dt;
   if first.USUBJID then call missing(VISIT1DT, TRTSDT, of __vis:);
   if VISITNUM = 1 then VISIT1DT = input(SVSTDTC, e8601da.);
   else if VISITNUM = 3 then TRTSDT = input(SVSTDTC, e8601da.);
   else if VISITNUM = 4 then __vis4dt = input(SVSTDTC, e8601da.);
   else if VISITNUM = 8 then __vis8dt = input(SVSTDTC, e8601da.);
   else if VISITNUM = 10 then __vis10dt = input(SVSTDTC, e8601da.);
   else if VISITNUM = 12 then __vis12dt = input(SVSTDTC, e8601da.);
   if last.USUBJID;
run;

/* primary diagnosis */
data src_mh;
   set SDTM.MH;
   where MHCAT = 'PRIMARY DIAGNOSIS';
   format DISONSDT date9.;
   if not missing(MHSTDTC) then DISONSDT = input(MHSTDTC, e8601da.);
   keep USUBJID DISONSDT;
run;

/* mini-mental state and ADAS-Cog and CIBIC post-baseline */
data src_qs;
   set SDTM.QS;
   by USUBJID;
   retain MMSETOT __effalz __effcli;
   if first.USUBJID then do;
      MMSETOT = 0;
      __effalz = 0;
      __effcli = 0;
   end;
   if QSCAT =: 'MINI' then MMSETOT = sum(MMSETOT, input(QSORRES, best.));
   if QSCAT =: 'ALZ' and VISITNUM > 3 then __effalz = 1;
   if QSCAT =: 'CLI' and VISITNUM > 3 then __effcli = 1;
   if last.USUBJID;
   keep USUBJID MMSETOT __eff:;
run;

/* exposure */
data ex;
   set SDTM.EX;
   format exstdt exendt date9.;
   if not missing(EXSTDTC) then exstdt = input(EXSTDTC, e8601da.);
   if not missing(EXENDTC) then exendt = input(EXENDTC, e8601da.);
   __visc = put(VISITNUM, Z2.);
run;

%macro extrans(suff = , var = );
   proc transpose data = ex
                  out = ex_&suff (drop = _:)
                  prefix = EX
                  suffix = &suff;
      by USUBJID;
      var &var;
      id __visc;
   run;
%mend extrans;

%extrans(suff = ST, var = exstdt)
%extrans(suff = EN, var = exendt)
%extrans(suff = DS, var = EXDOSE)

data src_ex;
   merge ex_:;
   by USUBJID;

   format TRTEDT date9.;
   if not missing(EX12ST) then TRTEDT = EX12EN;
   else if not missing(EX04ST) then TRTEDT = EX04EN;
   else if not missing(EX03ST) then TRTEDT = EX03EN;
run;
/********************************************/
/*** END SECTION TO RETRIEVE ALL THE DATA ***/
/********************************************/

resetline;
/*********************************************************************************/
/*** BEGIN SECTION TO COMBINE ALL THE SOURCE DATA AND CREATE REST OF VARIABLES ***/
/*********************************************************************************/
data adsl;
   merge src_:
         SDTM.SC (keep = USUBJID SCSTRESN SCTESTCD
                  where = (SCTESTCD = 'EDLEVEL')
                  rename = (SCSTRESN = EDUCLVL));
   by USUBJID;
   length SAFFL EFFFL $1 BMIBLGR1 $6  DURDSGR1 $4;
   if not missing(STUDYID);  /* STUDYID is only in src_dm */

   TRT01A = TRT01P;
   TRT01AN = TRT01PN;

   /* set population flags */
   SAFFL = ifc(not missing(TRTSDT), 'Y', 'N');
   EFFFL = ifc(__effalz = 1 and __effcli = 1, 'Y', 'N');

   /* CDISC has weight and height rounded to one decimal */
   if not missing(HEIGHTBL) then HEIGHTBL = round(HEIGHTBL, .1);
   if not missing(WEIGHTBL) then WEIGHTBL = round(WEIGHTBL, .1);
   if nmiss(HEIGHTBL, WEIGHTBL) = 0 then do;
      BMIBL = round(WEIGHTBL / ((HEIGHTBL / 100)**2), .1);
      if . < BMIBL < 25 then BMIBLGR1 = '<25';
      else if 25 <= BMIBL < 30 then BMIBLGR1 = '25-<30';
      else if BMIBL >= 30 then BMIBLGR1= '>=30';
   end;

   /* determine the number of months between diagnosis and visit 1 */
   *DURDIS = intck('month', DISONSDT, VISIT1DT, 'continuous');
   DURDIS = round((VISIT1DT - DISONSDT + 1) / (365.25/12), .1);
   if not missing(DURDIS) and DURDIS < 12 then DURDSGR1 = '<12';
   else if DURDIS >= 12 then DURDSGR1 = '>=12';

   if nmiss(__vis8dt, RFENDT) = 0 and RFENDT >= __vis8dt then COMP8FL = 'Y';
   else COMP8FL = 'N';
   if nmiss(__vis10dt, RFENDT) = 0 and RFENDT >= __vis10dt then COMP16FL = 'Y';
   else COMP16FL = 'N';
   if nmiss(__vis12dt, RFENDT) = 0 and RFENDT >= __vis12dt then COMP24FL = 'Y';
   else COMP24FL = 'N';

   /* if missing treatment end date and subject discontinued after visit 3 then set end of treatment to discontinuation */
   if missing(TRTEDT) and nmiss(RFENDT, TRTSDT) = 0 and RFENDT >= TRTSDT then TRTEDT = RFENDT;

   if nmiss(TRTSDT, TRTEDT) = 0 then TRTDUR = TRTEDT - TRTSDT + 1;

   /* calculate cumulative dose */
   if TRT01AN in (0 54) then CUMDOSE = TRTDUR * TRT01AN;
   else if TRT01AN = 81 then do;
      /* dosing interval 1 on 54 mg */
      if nmiss(__vis4dt, TRTSDT) = 0 then _doseint1 = min(TRTEDT, __vis4dt) - TRTSDT + 1;
      else if missing(__vis4dt) and nmiss(TRTSDT, RFENDT) = 0 and RFENDT > TRTSDT then _doseint1 = TRTEDT - TRTSDT + 1;
      if not missing(_doseint1) then ds_doseint1 = _doseint1 * 54;

      /* dosing interval 2 on 81 mg */
      if nmiss(__vis4dt, __vis12dt) = 0 then _doseint2 = min(TRTEDT, __vis12dt) - __vis4dt;
      else if missing(__vis12dt) and nmiss(__vis4dt, RFENDT) = 0 and RFENDT > __vis4dt then _doseint2 = TRTEDT - __vis4dt;
      if not missing(_doseint2) then ds_doseint2 = _doseint2 * 81;

      /* dosing interval 3 on 54 mg */
      if nmiss(__vis12dt, RFENDT) = 0 and RFENDT > __vis12dt then _doseint3 = TRTEDT - __vis12dt;
      if not missing(_doseint3) then ds_doseint3 = _doseint3 * 54;

      CUMDOSE = sum(of ds_doseint:);
   end;

   if nmiss(TRTDUR, CUMDOSE) = 0 then AVGDD = round(CUMDOSE / TRTDUR, .1);
run;
/*******************************************************************************/
/*** END SECTION TO COMBINE ALL THE SOURCE DATA AND CREATE REST OF VARIABLES ***/
/*******************************************************************************/

resetline;
/**********************************************/
/*** BEGIN SECTION TO CREATE FINAL DATA SET ***/
/**********************************************/
data ADAM.ADSL (label = 'Subject-Level Analysis Data');
   set adslskel adsl;
   keep &allvars;
run;

/* compare to the CDISC version */
proc compare base = CADAM.ADSL compare = ADAM.ADSL listall;
   id USUBJID;
run;
/********************************************/
/*** END SECTION TO CREATE FINAL DATA SET ***/
/********************************************/