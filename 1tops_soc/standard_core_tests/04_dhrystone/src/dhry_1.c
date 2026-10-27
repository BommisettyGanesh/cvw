/*
 * =============================================================================
 * Dhrystone 2.1 Benchmark Port for Pure RISC-V CPU Core (Bare-Metal RV32I)
 * Language: C
 * Measures: Dhrystones/sec, DMIPS, DMIPS/MHz, CPI, IPC
 * =============================================================================
 */

#include "dhry.h"
#include <stdio.h>
#include <stdint.h>

extern uint32_t rdcycle(void);
extern uint32_t rdinstret(void);
extern void tohost_exit(int code);

#ifndef NUMBER_OF_RUNS
#define NUMBER_OF_RUNS 100
#endif

/* Global Variables */
Rec_Pointer     Ptr_Glob,
                Next_Ptr_Glob;
int             Int_Glob;
Boolean         Bool_Glob;
char            Ch_1_Glob,
                Ch_2_Glob;
int             Arr_1_Glob [50];
int             Arr_2_Glob [50] [50];

static Rec_Type rec_buf1;
static Rec_Type rec_buf2;

/* Forward Declarations */
void Proc_1 (REG Rec_Pointer Ptr_Val_Par);
void Proc_2 (One_Fifty *Int_Par_Ref);
void Proc_3 (Rec_Pointer *Ptr_Ref_Par);
void Proc_4 (void);
void Proc_5 (void);
Boolean Func_2 (Str_30 Str_1_Par_Ref, Str_30 Str_2_Par_Ref);

int main (void)
{
        One_Fifty       Int_1_Loc;
  REG   One_Fifty       Int_2_Loc;
        One_Fifty       Int_3_Loc;
  REG   char            Ch_Index;
        Enumeration     Enum_Loc;
        Str_30          Str_1_Loc;
        Str_30          Str_2_Loc;
  REG   int             Run_Index;
  REG   int             Number_Of_Runs = NUMBER_OF_RUNS;
        uint32_t        start_cycles, end_cycles, user_cycles;
        uint32_t        start_inst, end_inst, user_inst;

  /* Static buffer allocation for bare-metal execution */
  Next_Ptr_Glob = &rec_buf1;
  Ptr_Glob      = &rec_buf2;

  Ptr_Glob->Ptr_Comp                    = Next_Ptr_Glob;
  Ptr_Glob->Discr                       = Ident_1;
  Ptr_Glob->variant.var_1.Enum_Comp     = Ident_3;
  Ptr_Glob->variant.var_1.Int_Comp      = 40;
  strcpy (Ptr_Glob->variant.var_1.Str_Comp, "DHRYSTONE PROGRAM, SOME STRING");
  strcpy (Str_1_Loc, "DHRYSTONE PROGRAM, 1'ST STRING");

  Arr_2_Glob [8][7] = 10;

  printf ("\n==================================================\n");
  printf ("     Dhrystone 2.1 Benchmark (RV32I Core)         \n");
  printf ("==================================================\n");
  printf ("Target Core  : Pure riscv_cpu Core (Core Only)\n");
  printf ("Memory Model : AMBA 3 AHB-Lite Synchronous RAM\n");
  printf ("Runs Count   : %d\n", Number_Of_Runs);
  printf ("Starting benchmark execution...\n\n");

  /* Start Timing */
  start_inst   = rdinstret();
  start_cycles = rdcycle();

  for (Run_Index = 1; Run_Index <= Number_Of_Runs; ++Run_Index)
  {
    Proc_5();
    Proc_4();
    Int_1_Loc = 2;
    Int_2_Loc = 3;
    strcpy (Str_2_Loc, "DHRYSTONE PROGRAM, 2'ND STRING");
    Enum_Loc = Ident_2;
    Bool_Glob = ! Func_2 (Str_1_Loc, Str_2_Loc);
    while (Int_1_Loc < Int_2_Loc)
    {
      Int_3_Loc = 5 * Int_1_Loc - Int_2_Loc;
      Proc_7 (Int_1_Loc, Int_2_Loc, &Int_3_Loc);
      Int_1_Loc += 1;
    }
    Proc_8 (Arr_1_Glob, Arr_2_Glob, Int_1_Loc, Int_3_Loc);
    Proc_1 (Ptr_Glob);
    for (Ch_Index = 'A'; Ch_Index <= Ch_2_Glob; ++Ch_Index)
    {
      if (Enum_Loc == Func_1 (Ch_Index, 'C'))
      {
        Proc_6 (Ident_1, &Enum_Loc);
        strcpy (Str_2_Loc, "DHRYSTONE PROGRAM, 3'RD STRING");
        Int_2_Loc = Run_Index;
        Int_Glob = Run_Index;
      }
    }
    Int_2_Loc = Int_2_Loc * Int_1_Loc;
    Int_1_Loc = Int_2_Loc / Int_3_Loc;
    Int_2_Loc = 7 * (Int_2_Loc - Int_3_Loc) - Int_1_Loc;
    Proc_2 (&Int_1_Loc);
  }

  /* Stop Timing */
  end_cycles  = rdcycle();
  end_inst    = rdinstret();
  user_cycles = end_cycles - start_cycles;
  user_inst   = end_inst - start_inst;

  printf ("--- Execution Verification ---\n");
  printf ("  Int_Glob        : %d (expected 5)\n", Int_Glob);
  printf ("  Bool_Glob       : %d (expected 1)\n", Bool_Glob);
  printf ("  Ch_1_Glob       : %c (expected A)\n", Ch_1_Glob);
  printf ("  Ch_2_Glob       : %c (expected B)\n", Ch_2_Glob);
  printf ("  Arr_1_Glob[8]   : %d (expected 7)\n", Arr_1_Glob[8]);
  printf ("  Arr_2_Glob[8][7]: %d (expected %d)\n", Arr_2_Glob[8][7], Number_Of_Runs + 10);
  printf ("  Int_1_Loc       : %d (expected 5)\n", Int_1_Loc);
  printf ("  Int_2_Loc       : %d (expected 13)\n", Int_2_Loc);
  printf ("  Int_3_Loc       : %d (expected 7)\n", Int_3_Loc);

  /* Check Results */
  int error = 0;
  if (Int_Glob != 5) error++;
  if (Bool_Glob != 1) error++;
  if (Ch_1_Glob != 'A') error++;
  if (Ch_2_Glob != 'B') error++;
  if (Arr_1_Glob[8] != 7) error++;
  if (Arr_2_Glob[8][7] != Number_Of_Runs + 10) error++;
  if (Int_1_Loc != 5) error++;
  if (Int_2_Loc != 13) error++;
  if (Int_3_Loc != 7) error++;

  printf ("\n--- Hardware Performance Report ---\n");
  printf ("  Total Benchmark Cycles : %u\n", user_cycles);
  printf ("  Total Instructions     : %u\n", user_inst);

  if (user_inst > 0 && user_cycles > 0)
  {
    uint32_t cpi_int  = user_cycles / user_inst;
    uint32_t cpi_frac = ((user_cycles % user_inst) * 100) / user_inst;
    printf ("  Core CPI               : %u.%02u\n", cpi_int, cpi_frac);
    printf ("  Core IPC               : 0.%02u\n", (user_inst * 100) / user_cycles);

    /* Cycles per Dhrystone loop */
    uint32_t cycles_per_run = user_cycles / Number_Of_Runs;
    printf ("  Cycles per Dhrystone   : %u\n", cycles_per_run);

    /* Frequency: 50 MHz reference */
    /* Dhrystones/sec = (50,000,000 / cycles_per_run) */
    uint32_t dhry_per_sec = (50000000) / cycles_per_run;
    printf ("  Dhrystones per Second  : %u\n", dhry_per_sec);

    /* DMIPS = Dhrystones / 1757 (VAX benchmark standard) */
    uint32_t dmips = dhry_per_sec / 1757;
    printf ("  DMIPS                  : %u\n", dmips);

    /* DMIPS/MHz = (dhry_per_sec * 100) / (1757 * 50) */
    uint32_t dmips_per_mhz_int  = (dhry_per_sec * 100) / (1757 * 50);
    printf ("  DMIPS/MHz              : %u.%02u\n", dmips_per_mhz_int / 100, dmips_per_mhz_int % 100);
  }
  printf ("==================================================\n");

  if (error == 0)
  {
    printf (">>> DHRYSTONE 2.1 VERIFICATION SUCCESSFUL! <<<\n\n");
    tohost_exit(1);
  }
  else
  {
    printf (">>> DHRYSTONE 2.1 VERIFICATION FAILED (%d errors)! <<<\n\n", error);
    tohost_exit(0);
  }

  return 0;
}

void Proc_1 (REG Rec_Pointer Ptr_Val_Par)
{
  REG Rec_Pointer Next_Record = Ptr_Val_Par->Ptr_Comp;
  structassign (*Ptr_Val_Par->Ptr_Comp, *Ptr_Glob);
  Ptr_Val_Par->variant.var_1.Int_Comp = 5;
  Next_Record->variant.var_1.Int_Comp = Ptr_Val_Par->variant.var_1.Int_Comp;
  Next_Record->Ptr_Comp = Ptr_Val_Par->Ptr_Comp;
  Proc_3 ((Rec_Pointer *) &Next_Record->Ptr_Comp);
  if (Next_Record->Discr == Ident_1)
  {
    Next_Record->variant.var_1.Int_Comp = 6;
    Proc_6 (Ptr_Val_Par->variant.var_1.Enum_Comp, 
           &Next_Record->variant.var_1.Enum_Comp);
    Next_Record->Ptr_Comp = Ptr_Glob->Ptr_Comp;
    Proc_7 (Next_Record->variant.var_1.Int_Comp, 10, 
           &Next_Record->variant.var_1.Int_Comp);
  }
  else
    structassign (*Ptr_Val_Par, *Ptr_Val_Par->Ptr_Comp);
}

void Proc_2 (One_Fifty *Int_Par_Ref)
{
  One_Fifty  Int_Loc;
  Enumeration Enum_Loc;

  Int_Loc = *Int_Par_Ref + 10;
  do
    if (Ch_1_Glob == 'A')
    {
      Int_Loc -= 1;
      *Int_Par_Ref = Int_Loc - Int_Glob;
      Enum_Loc = Ident_1;
    }
  while (Enum_Loc != Ident_1);
}

void Proc_3 (Rec_Pointer *Ptr_Ref_Par)
{
  if (Ptr_Glob != Null)
    *Ptr_Ref_Par = Ptr_Glob->Ptr_Comp;
  Proc_7 (10, Int_Glob, &Ptr_Glob->variant.var_1.Int_Comp);
}

void Proc_4 (void)
{
  Boolean Bool_Loc;

  Bool_Loc = Ch_1_Glob == 'A';
  Bool_Glob = Bool_Loc | Bool_Glob;
  Ch_2_Glob = 'B';
}

void Proc_5 (void)
{
  Ch_1_Glob = 'A';
  Bool_Glob = false;
}
