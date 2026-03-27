unit unitdispatcher;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  Spin, comUnit;

type

  //***************************************
  //Production plan obtained by ERP and available in the DB
  // Enumerated: defines the type of the TTask
  TTask_Type  = (Type_Expedition = 1, Type_Delivery, Type_Production, Type_Trash);

  // TBC by a Query to DB
  TProduction_Order = record
    part_type           : Integer;    // Part type { 0, ... 9}
    part_numbers        : Integer;    // Number of parts to be performed
    order_type          : TTask_Type;
  end;

  TArray_Production_Order = array of TProduction_Order; // This array shall be completed by the SQL query
  //***************************************



  //***************************************
  // Dispatcher Execution
  // Enumerated: defines all stages of TTasks
  TStage      = (Stage_To_Be_Started = 1, Stage_GetPart, Stage_Unload, Stage_To_AR_Out, Stage_wait, Stage_Clear_Pos_AR,Stage_Production, Stage_Load, Stage_Update_Pos_AR, Stage_Finished, Stage_GetPosition, Stage_Inbound, Stage_Get_Free_Position, Stage_Update_Pos_AR_1);   //TbC

  // Data structure for holding one Task (OE, OD, OP)
  TTask = record
   task_type           : TTask_Type; // type
   current_operation   : TStage;     // the stage that is currently activ.
   part_type           : Integer;    // Part type { 0, ... 9}
   part_position_AR    : Integer;    // Part Position in AR (if needed)
   part_destination    : Integer;    // Part destination
  end;

  TArray_Task = array of TTask;      // NOTE: this "type" will originate a variable to hold the output from the scheduling ("sequenciador").
  //***************************************


  //***************************************
  // Availability of the resources in the shopfloor:
  TResources = record
   AR_free      : Boolean;    // true (free) or false (busy)
   AR_In_Part   : integer;    // Com uma peça do tipo P={0..9} (0=sem peça)
   AR_Out_Part  : integer;    // Com uma peça do tipo P={0..9} (0=sem peça)
   Robot_1_Part : integer;    // Com uma peça do tipo P={0..9} (0=sem peça)
   Robot_2_Part : integer;    // Com uma peça do tipo P={0..9} (0=sem peça)
   Inbound_free : Boolean;    // true (free) or false (busy)
  end;
  //***************************************



  { TFormDispatcher }
  TFormDispatcher = class(TForm)
    BStart: TButton;
    BExecute: TButton;
    BInitiatilize: TButton;
    GroupBox_log: TGroupBox;
    GroupBox_Production: TGroupBox;
    GroupBox_Stock: TGroupBox;
    Label_Lid: TLabel;
    Label_Base: TLabel;
    Label_Raw_material: TLabel;
    Memo_Log: TMemo;
    Panel_green: TPanel;
    Panel_gray: TPanel;
    Panel_Blue: TPanel;
    SpinEdit_Raw_Green: TSpinEdit;
    SpinEdit_Raw_Gray: TSpinEdit;
    SpinEdit_Base_Blue: TSpinEdit;
    SpinEdit_Base_Green: TSpinEdit;
    SpinEdit_Base_Gray: TSpinEdit;
    SpinEdit_Lid_Blue: TSpinEdit;
    SpinEdit_Lid_green: TSpinEdit;
    SpinEdit_Lid_gray: TSpinEdit;
    SpinEdit_Raw_Blue: TSpinEdit;
    Timer1: TTimer;
    procedure BExecuteClick(Sender: TObject);
    procedure BInitiatilizeClick(Sender: TObject);
    procedure BStartClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure GroupBox_ProductionClick(Sender: TObject);
    procedure Label_RawClick(Sender: TObject);
    procedure Memo_LogChange(Sender: TObject);
    procedure Timer1Timer(Sender: TObject);
  private

  public
    procedure Dispatcher(var tasks:TArray_Task; var idx : integer; shopfloor: TResources );
    procedure Execute_Expedition_Order(var task:TTask; shopfloor: TResources );
    procedure Execute_Production_Order(var task:TTask; shopfloor: TResources );
    procedure Execute_Delivery_Order(var task:TTask; shopfloor: TResources );
    function GET_AR_Position (Part : integer; Warehouse : array of integer): integer;
    function GET_AR_Free_Position(Warehouse : array of integer): integer;
    procedure SET_AR_Position (idx : integer; Part : integer; var Warehouse : array of integer);

  end;

const
  //ID for Parts to be used by FIO
  Part_Raw_Blue   = 1;
  Part_Raw_Green  = 2;
  Part_Raw_Grey   = 3;
  Part_Base_Blue  = 4;
  Part_Base_Green = 5;
  Part_Base_Grey  = 6;
  Part_Lid_Blue   = 7;
  Part_Lid_Green  = 8;
  Part_Lid_Grey   = 9;


(* GLOBAL VARIABLES *)
var
  FormDispatcher : TFormDispatcher;

  // Production orders obtained by the ERP (using the SQL Query)
  Production_Orders : TArray_Production_Order;

  // Availability of resources (needs to be updated over time)
  ShopResources : TResources;

  // Tasks that need to be concluded by the MES (expedition, delivery, production and trash).
  ShopTasks     : TArray_Task;

  // Index of the task (from the array "ShopTasks") that is being executed.
  idx_Task_Executing : integer;

  // Status of each cell in the warehouse.
  WAREHOUSE_Parts           : array of integer;         //warehouse parts in each position

implementation

{$R *.lfm}





{ Procedure that checks the status of the resources available on the shop floor }
procedure UpdateResources(var shopfloor: TResources);
var
    resp : array[1..8] of integer;
begin
  {'FactoryIO state',
   'Inbound state',
   'Warehouse_state',
   'Warehouse input conveyor part',
   'Warehouse output conveyor part',
   'Cell 1 part',
   'Cell 2 part',
   'Pick & Place part'
   }
  resp:=M_Get_Factory_Status();

  with shopfloor do
  begin
    Inbound_free := Int(resp[2]) = 1;
    AR_free      := Int(resp[3]) = 1;
    AR_In_Part   := LongInt(resp[4]);
    AR_Out_Part  := LongInt(resp[5]);
    Robot_1_Part := LongInt(resp[6]);
    Robot_2_Part := LongInt(resp[7]);
  end;
end;


{ Procedure that received TArray_Production_Order and converts to TArray_Task
-> INPUT: TArray_Production_Order
-> OUTPUT: TArray_Task
}
procedure SimpleScheduler(var orders: TArray_Production_Order; var tasks:TArray_Task );
var
    current_task     : TTask;
    idx_order        : integer;
    numb_tasks_total : integer = 0;       // total number of tasks created in "tasks"
    numb_same_task   : integer = 0;

begin
  for idx_order:= 0 to Length(orders)-1 do
  begin
      with current_task do
      begin
        numb_same_task    := 0;

        task_type         := orders[idx_order].order_type;
        part_type         := orders[idx_order].part_type;
        current_operation := Stage_To_Be_Started;

        part_position_AR  := -1;  // to be defined later.   STUDENTS MUST CHANGE

        if( part_type < Part_Lid_Blue )then
        begin
             part_destination  := 1;     // if bases (Exit 1 or Cell 1)
        end else
        begin
            part_destination  := 2;     // if bases (Exit 2 or Cell 2)
        end;

        //Create  orders[idx_order].part_numbers of the same TTask for Dispatcher.
        numb_tasks_total :=  Length(tasks);
        SetLength(tasks,  numb_tasks_total + orders[idx_order].part_numbers);
        for numb_same_task := 0 to orders[idx_order].part_numbers-1 do
        begin
            tasks[numb_tasks_total+numb_same_task] := current_task;
        end;
      end;
  end;

end;




// Query DB -> Scheduling -> Connect PLC for Dispatching
procedure TFormDispatcher.BStartClick(Sender: TObject);
var
    result           : integer;
    production_order : TProduction_Order;
begin
  // ******************************************
  // Query to DB and converts data to structures
  // ...      to be completed by the STUDENT after SQL introduction in INFI.
  // *******************************************




  // ******************************************
  // Simulating the result of the SQL query:
  SetLength(Production_Orders, 5);                   //Let's create only some Orders to use as an example. STUDENT MUST CHANGE ACCORDING TO REQUIREMENTS

  //Expedition

  production_order.order_type   := Type_Expedition ;
  production_order.part_numbers := 2;
  production_order.part_type    := Part_Base_Blue;    //Blue Base
  Production_Orders[0]          := production_order;  //Saving..

  production_order.order_type   := Type_Expedition ;  //Expedition
  production_order.part_numbers := 2;
  production_order.part_type    := Part_Lid_Green;    //Green Lids
  Production_Orders[1]          := production_order;  //Saving..

  production_order.order_type     := Type_Delivery ;    //Inbounds
  production_order.part_numbers   := 1;
  production_order.part_type      := Part_Raw_Blue;     //Blue Raw Material
  Production_Orders[2]            := production_order;

  production_order.order_type     := Type_Production;   //Production
  production_order.part_numbers   := 1;
  production_order.part_type      := Part_Base_Blue;     //Blue Base
  Production_Orders[3]            := production_order;
  (*
  production_order.order_type     := Type_Expedition;   //Expedition
  production_order.part_numbers   := 1;
  production_order.part_type      := 4;                    //Green Base
  Production_Orders[4]            := production_order;
  *)
  // ******************************************

  // for Scheduling
  idx_Task_Executing := 0;

  //Connecting to PLC
  result := M_connect();

  if (result = 1) then
    BStart.Caption:='Connected to PLC'
  else
  begin
    BStart.Caption:='Start';
    ShowMessage('PLC unavailable. Please try again!');
   end;
end;

procedure TFormDispatcher.FormCreate(Sender: TObject);
begin
  SetLength(ShopTasks, 0);
  idx_Task_Executing := 0;
end;

procedure TFormDispatcher.GroupBox_ProductionClick(Sender: TObject);
begin

end;

procedure TFormDispatcher.Label_RawClick(Sender: TObject);
begin

end;

procedure TFormDispatcher.Memo_LogChange(Sender: TObject);
begin

end;

procedure TFormDispatcher.Timer1Timer(Sender: TObject);
begin
  BExecuteClick(Self);
end;




//Initialization of the MES /week. This procedure run only once per week
procedure TFormDispatcher.BInitiatilizeClick(Sender: TObject);
var
  cel, i: integer;
  freePosition: integer;
begin
  Memo_Log.Append('Innitializing Warehouse');

  //Clean warehouse memory
  SetLength(WAREHOUSE_Parts, 55);
  for cel := 1 to 54 do
  begin
    WAREHOUSE_Parts[cel] := 0;
  end;

  freePosition := 1;

if SpinEdit_Raw_Blue.Value + SpinEdit_Raw_Green.Value + SpinEdit_Raw_Gray.Value + SpinEdit_Base_Blue.Value + SpinEdit_Base_Green.Value + SpinEdit_Base_Gray.Value + SpinEdit_Lid_Blue.Value + SpinEdit_Lid_green.Value + SpinEdit_Lid_gray.Value < 5 then
begin
  for i := 1 to SpinEdit_Raw_Blue.Value do
  begin
    M_Initialize(freePosition, Part_Raw_Blue);
    WAREHOUSE_Parts[freePosition] := Part_Raw_Blue;
    freePosition := freePosition + 9; // next position
    Sleep(1500);
  end;

  for i := 1 to SpinEdit_Raw_Green.Value do
  begin
    M_Initialize(freePosition, Part_Raw_Green);
    WAREHOUSE_Parts[freePosition] := Part_Raw_Green;
    freePosition := freePosition + 9; // next position
    Sleep(1500);
  end;

    for i := 1 to SpinEdit_Raw_Gray.Value do
  begin
    M_Initialize(freePosition, Part_Raw_Grey);
    WAREHOUSE_Parts[freePosition] := Part_Raw_Grey;
    freePosition := freePosition + 9; // next position
    Sleep(1500);
  end;

    for i := 1 to SpinEdit_Lid_Blue.Value do
  begin
    M_Initialize(freePosition, Part_Lid_Blue);
    WAREHOUSE_Parts[freePosition] := Part_Lid_Blue;
    freePosition := freePosition + 9; // next position
    Sleep(1500);
  end;

      for i := 1 to SpinEdit_Lid_Green.Value do
  begin
    M_Initialize(freePosition, Part_Lid_Green);
    WAREHOUSE_Parts[freePosition] := Part_Lid_Green;
    freePosition := freePosition + 9; // next position
    Sleep(1500);
    end;

        for i := 1 to SpinEdit_Lid_Gray.Value do
  begin
    M_Initialize(freePosition, Part_Lid_Grey);
    WAREHOUSE_Parts[freePosition] := Part_Lid_Grey;
    freePosition := freePosition + 9; // next position
    Sleep(1500);
  end;

        for i := 1 to SpinEdit_Base_Blue.Value do
  begin
    M_Initialize(freePosition, Part_Base_Blue);
    WAREHOUSE_Parts[freePosition] := Part_Base_Blue;
    freePosition := freePosition + 9; // next position
    Sleep(1500);
  end;

            for i := 1 to SpinEdit_Base_Green.Value do
  begin
    M_Initialize(freePosition, Part_Base_Green);
    WAREHOUSE_Parts[freePosition] := Part_Base_Green;
    freePosition := freePosition + 9; // next position
    Sleep(1500);
  end;

            for i := 1 to SpinEdit_Base_Gray.Value do
  begin
    M_Initialize(freePosition, Part_Base_Grey);
    WAREHOUSE_Parts[freePosition] := Part_Base_Grey;
    freePosition := freePosition + 9; // next position
    Sleep(1500);
  end;

  end;

  SimpleScheduler(Production_Orders, ShopTasks);
  Timer1.Enabled := true;
  Memo_log.Append('Warehouse successfully innitiated!');
end;



(*
var
    cel, r: integer;
begin
  // *********************************************************
  // WAREHOUSE MANAGEMENT

  // Initialization of parts in the first column of the warehouse.
  r := M_Initialize(1, Part_Base_Blue);
  sleep(1500);
  r := r + M_Initialize(10, Part_Base_Blue);
  sleep(1500);
  r := r + M_Initialize(19, Part_Lid_Green);
  sleep(1500);
  r := r + M_Initialize(28, Part_Lid_Green);

  if( r > 4) then
    Memo_Log.Append('Innitiatialization with errors');


  //Update the Warehouse according to the previous innitialization
  SetLength(WAREHOUSE_Parts, 55);                //Parts in the warehouse   55-1 = 54 to start in 1
  for  cel := 1 to  Length(WAREHOUSE_Parts)-1 do
  begin
      WAREHOUSE_Parts[cel] := 0;
  end;
  WAREHOUSE_Parts[1]       := Part_Base_Blue;
  WAREHOUSE_Parts[10]      := Part_Base_Blue;
  WAREHOUSE_Parts[19]      := Part_Lid_Green;
  WAREHOUSE_Parts[28]      := Part_Lid_Green;


  //Converts ProductionOrders to Tasks (staged activities)
  SimpleScheduler(Production_Orders, ShopTasks);


  // Starting Dispatcher Iterations over time
  Timer1.Enabled:= true;
end;

*)

// get the first position (cell) in AR that contains the "Part"
function TFormDispatcher.GET_AR_Position (Part : integer; Warehouse : array of integer): integer;
var
    i : integer;
begin
  for i := 0 to Length(Warehouse)-1 do
  begin
      if Warehouse[i] = Part then
      begin
          result := i;
          Exit;
      end;
  end;
end;

// Função que permite obter a primeira posição vazia da primeira coluna do armazém
function TFormDispatcher.GET_AR_Free_Position(Warehouse : array of integer): integer;
var
    i : integer;
begin
  result := -1;

  for i := 1 to Length(Warehouse)-1 do
  begin
      if Warehouse[9*i - 8] = 0 then
      begin
          result := 9*i - 8;
          Exit;
      end;
  end;
end;




//Sets the Position of the AR with the "Part" provided
procedure TFormDispatcher.SET_AR_Position (idx : integer; Part : integer; var Warehouse : array of integer);
begin
  Warehouse [ idx ] := Part;
end;




procedure TFormDispatcher.BExecuteClick(Sender: TObject);
begin
  // See the availability of resources
  UpdateResources(ShopResources);


  //Dispatcher executing per cycle.
  if(Length(ShopTasks)>0) then begin
    Dispatcher(ShopTasks, idx_Task_Executing, ShopResources);
  end;
end;



// Global Dispatcher - SIMPLEX
procedure TFormDispatcher.Dispatcher(var tasks:TArray_Task; var idx : integer; shopfloor: TResources );
begin
    case tasks[idx].task_type of

      // Expedition
      Type_Expedition :
      begin
        if(idx < Length(tasks)) then
        begin
          Memo_Log.Append('Task Expedition');
          Execute_Expedition_Order(tasks[idx], shopfloor);

          // Next Operation to be executed.
          if(tasks[idx].current_operation = Stage_Finished) then
            inc(idx_Task_Executing);
        end;
      end;


      // Production
      Type_Production :
      begin
        if(idx < Length(tasks)) then
                begin
                  Memo_Log.Append('Task Production');
                  Execute_Production_Order(tasks[idx], shopfloor);

                  // Next Operation to be executed.
                  if(tasks[idx].current_operation = Stage_Finished) then
                    inc(idx_Task_Executing);
                end;
      end;


      // Inbound
      Type_Delivery :
      begin
        if(idx < Length(tasks)) then
                begin
                  Memo_Log.Append('Task Delivery');
                  Execute_Delivery_Order(tasks[idx], shopfloor);

                  // Next Operation to be executed.
                  if(tasks[idx].current_operation = Stage_Finished) then
                    inc(idx_Task_Executing);
                end;
      end;

      // Trash
      Type_Trash :
      begin
        //todo
      end;

    end;
end;


// Procedure that executes an expedition order according to SLIDE 19 of T classes.
procedure TFormDispatcher.Execute_Expedition_Order(var task:TTask; shopfloor: TResources );
var
    r : integer;
begin
  //  TStage      = (Stage_To_Be_Started = 1, Stage_GetPart, Stage_Unload, Stage_To_AR_Out, Stage_Clear_Pos_AR, Stage_Finished);   //TbC

  with task do
  begin
     case current_operation of

        // To be Started
        Stage_To_Be_Started:
        begin
           current_operation :=  Stage_GetPart;
        end;

        // Getting a Position from the Warehouse
        Stage_GetPart :
        begin
          if(shopfloor.AR_free) then  //AR is free
          begin
            Part_Position_AR := GET_AR_Position(Part_Type, WAREHOUSE_Parts);
            Memo_Log.Append(IntToStr(Part_Position_AR));

            if( Part_Position_AR > 0 ) then
            begin
               current_operation :=  Stage_Unload;
            end
            else
            begin
               current_operation :=  Stage_GetPart;
            end;
          end;
        end;

        // Request to unload that part
        Stage_Unload :
        begin
          Memo_Log.Append('AR Unloading: ' + IntToStr(Part_Position_AR));
          r := M_Unload(Part_Position_AR);

          if ( r = 1 ) then                                 //sucess
             current_operation :=  Stage_To_AR_Out;
        end;

        // Part is in the output conveyor
        Stage_To_AR_Out :
        begin
          if( ShopResources.AR_Out_Part  = Part_Type ) then
          begin
            r := M_Do_Expedition(Part_Destination);          // Expedition

            if( r = 1) then                                  // sucess
             current_operation :=  Stage_Clear_Pos_AR;
          end;
        end;

        //Updated AR (removing the part from the position)
        Stage_Clear_Pos_AR :
        begin
          SET_AR_Position(Part_Position_AR, 0, WAREHOUSE_Parts);
          current_operation :=  Stage_Finished;
        end;

        //Done.
        Stage_Finished :
        begin
          current_operation :=  Stage_Finished;
        end;
      end;
  end;
end;


// Procedure that executes a Production order.
procedure TFormDispatcher.Execute_Production_Order(var task:TTask; shopfloor: TResources );
var
    r : integer;
begin
  //  TStage      = (Stage_To_Be_Started = 1, Stage_GetPart, Stage_Unload, Stage_Clear_Pos_AR,
  // Stage_Production, Stage_Load, Stage_Update_Pos_AR, Stage_Finished);

  with task do
  begin
     case current_operation of

        // To be Started
        Stage_To_Be_Started:
        begin
           current_operation :=  Stage_GetPart;
        end;

        // Getting a Position from the Warehouse
        Stage_GetPart :
        begin
          if(shopfloor.AR_free) then  //AR is free
          begin
            if Part_Destination = 1 then
            begin

               Part_Position_AR := GET_AR_Position((Part_Type - 3), WAREHOUSE_Parts);
               Memo_Log.Append('Getting Part from Position' + IntToStr(Part_Position_AR));
            end
            else
            begin
                Part_Position_AR := GET_AR_Position(Part_Type - 6, WAREHOUSE_Parts); //Raw Part to Get
                Memo_Log.Append('Getting Part from Position' + IntToStr(Part_Position_AR));
            end;
            if( Part_Position_AR > 0 ) then
            begin
               current_operation :=  Stage_Unload;
            end
            else
            begin
               current_operation :=  Stage_GetPart;
            end;
          end;
        end;

        // Request to unload that part
        Stage_Unload :
        begin
          Memo_Log.Append('AR Unloading: ' + IntToStr(Part_Position_AR));
          r := M_Unload(Part_Position_AR);

          if ( r = 1 ) then                                 //sucess
             current_operation :=  Stage_Clear_Pos_AR;
        end;


        //Updated AR (removing the part from the position)
        Stage_Clear_Pos_AR :
        begin
          SET_AR_Position(Part_Position_AR, 0, WAREHOUSE_Parts);
          current_operation :=  Stage_Production;
        end;

        //Send a part to production
        Stage_Production:
        begin
          if (shopfloor.AR_Out_Part = (Part_Type - 3)) then
          begin
            if Part_Destination = 1 then
              Memo_Log.Append('Producing Base')
            else
              Memo_Log.Append('Producing Lid');

            r := M_Do_Production(Part_Destination);
            Memo_Log.Append(IntToStr(r) + ' ' + IntToStr(Part_Destination));
            Memo_Log.Append(IntToStr(part_type));

            if (r = 1) then
              current_operation := Stage_Wait;
          end;
        end;

        Stage_Wait:
        begin
        if (shopfloor.AR_In_Part <> 0) then
        begin
          current_operation := Stage_GetPosition;
        end;
      end;


        // Getting a Free Position from the Warehouse
        Stage_GetPosition :
        begin
          if(shopfloor.AR_free) and (shopfloor.AR_In_Part <> 0) then  //AR is free
          begin
            Memo_Log.append('Position acquired.');
            if( Part_Position_AR > 0 ) then
            begin
               current_operation :=  Stage_Load;
            end
            else
            begin
               current_operation :=  Stage_GetPosition;
            end;
          end;
        end;

        // Request to Load that part
        Stage_Load :
        begin
          Memo_Log.Append('AR Loading to Position: ' + IntToStr(Part_Position_AR));
          r := M_Load(Part_Position_AR);

          if ( r = 1 ) then                                 //sucess
             current_operation :=  Stage_Update_Pos_AR;
        end;

        //Update the Position in the AR
        Stage_Update_Pos_AR :
        begin
          SET_AR_Position(Part_Position_AR, Part_Type, WAREHOUSE_Parts);    //is this right?
          current_operation :=  Stage_Finished;
        end;

        //Done.
        Stage_Finished :
        begin
          current_operation :=  Stage_Finished;
        end;
      end;
  end;
end;

// Procedure that executes a Delivery order.
procedure TFormDispatcher.Execute_Delivery_Order(var task:TTask; shopfloor: TResources ); //por etapas no inicio
var
    r : integer;
begin
  with task do
  begin
     case current_operation of

        Stage_To_Be_Started:
        begin
           current_operation :=  Stage_Get_Free_Position;
        end;

        Stage_Get_Free_Position:

                begin
                   Part_Position_AR := GET_AR_Free_Position(WAREHOUSE_Parts);

                   if (Part_Position_AR > 0) then
                   begin
                      //Found space
                      r := M_Do_Inbound(Part_Type);
                      if (r = 1) then
                      begin
                         current_operation := Stage_Inbound;
                      end;
                   end
                   else
                   begin
                      Memo_Log.Append('Warehouse is full!');
                   end;
                end;

         Stage_Inbound :

        begin
          if (shopfloor.AR_In_Part <> 0) then  // just wait for any part to arrive
          begin
          current_operation := Stage_Load;
          end;
        end;

        // Wait for part
        Stage_Load:
        begin
           if (shopfloor.AR_free) and (shopfloor.AR_In_Part <> 0) then
           begin
              Memo_Log.Append('Loading part into position ' + IntToStr(Part_Position_AR));
              r := M_Load(Part_Position_AR);

              if (r = 1) then
                 current_operation := Stage_Update_Pos_AR_1;
           end;
        end;

        // Update the warehouse position.
        Stage_Update_Pos_AR_1:
        begin
           SET_AR_Position(Part_Position_AR, Part_Type, WAREHOUSE_Parts);
           Memo_Log.Append('Inbound successfully concluded. Part stored into position ' + IntToStr(Part_Position_AR));

           current_operation := Stage_Finished;
        end;

        Stage_Finished:
        begin
           current_operation := Stage_Finished;
        end;

     end;
  end;
end;

end.

