unit unitdispatcher;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  Spin, Grids, comUnit;

type

  //***************************************
  //Production plan obtained by ERP and available in the DB
  // Enumerated: defines the type of the TTask
  TTask_Type  = (Type_Expedition = 1, Type_Delivery, Type_Production);

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
  TStage      = (Stage_To_Be_Started = 1, Stage_GetPart, Stage_Unload, Stage_To_AR_Out, Stage_wait, Stage_Clear_Pos_AR,Stage_Production, Stage_Load, Stage_Update_Pos_AR, Stage_Finished, Stage_GetPosition, Stage_Inbound, Stage_Get_Free_Position, Stage_Update_Pos_AR_1);

  // Data structure for holding one Task (OE, OD, OP)
  TTask = record
   task_type           : TTask_Type; // type
   current_operation   : TStage;     // the stage that is currently activ.
   part_type           : Integer;    // Part type { 0, ... 9}
   part_position_AR    : Integer;    // Part Position in AR (if needed)
   part_destination    : Integer;    // Part destination
   order_index         : Integer;
   is_grey             : Boolean;    // true if grey part moving in the factory
   time_start          : QWord;
   time_wait_AR        : QWord;

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
    Button_Add_Order: TButton;
    ComboBox1: TComboBox;
    ComboBox2: TComboBox;
    ComboBox3: TComboBox;
    GroupBox_Monitor: TGroupBox;
    GroupBox_controls: TGroupBox;
    GroupBox_log: TGroupBox;
    GroupBox_Production: TGroupBox;
    GroupBox_Stock: TGroupBox;
    label_quantity: TLabel;
    Label_Order: TLabel;
    Label_Type: TLabel;
    Label_Colour: TLabel;
    Label_Lid: TLabel;
    Label_Base: TLabel;
    Label_Raw_material: TLabel;
    Memo_Log: TMemo;
    Panel_green: TPanel;
    Panel_gray: TPanel;
    Panel_Blue: TPanel;
    SpinEdit_Quantity: TSpinEdit;
    SpinEdit_Raw_Green: TSpinEdit;
    SpinEdit_Raw_Gray: TSpinEdit;
    SpinEdit_Base_Blue: TSpinEdit;
    SpinEdit_Base_Green: TSpinEdit;
    SpinEdit_Base_Gray: TSpinEdit;
    SpinEdit_Lid_Blue: TSpinEdit;
    SpinEdit_Lid_green: TSpinEdit;
    SpinEdit_Lid_gray: TSpinEdit;
    SpinEdit_Raw_Blue: TSpinEdit;
    StringGrid1: TStringGrid;
    StringGrid2: TStringGrid;
    Timer1: TTimer;
    procedure BExecuteClick(Sender: TObject);
    procedure BInitiatilizeClick(Sender: TObject);
    procedure BStartClick(Sender: TObject);
    procedure Button_Add_OrderClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure GroupBox_MonitorClick(Sender: TObject);
    procedure GroupBox_ProductionClick(Sender: TObject);
    procedure Label_RawClick(Sender: TObject);
    procedure Memo_LogChange(Sender: TObject);
    procedure SpinEdit_Base_BlueChange(Sender: TObject);
    procedure Timer1Timer(Sender: TObject);
  private

  public
    procedure Dispatcher(var tasks:TArray_Task; shopfloor: TResources );
    procedure Execute_Expedition_Order(var task:TTask; shopfloor: TResources );
    procedure Execute_Production_Order(var task:TTask; shopfloor: TResources );
    procedure Execute_Delivery_Order(var task:TTask; shopfloor: TResources );
    function GET_AR_Position (Part : integer; Warehouse : array of integer): integer;
    function GET_AR_Free_Position(Warehouse : array of integer): integer;
    procedure SET_AR_Position (idx : integer; Part : integer; var Warehouse : array of integer);
    procedure UpdateMonitoringGrid;

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

  Monitoring_Received     : array[1..9] of integer;
  Monitoring_Expedited    : array[1..9] of integer;
  Monitoring_InProduction : array[1..9] of integer;  // for counting how many parts recieved, expedtied and in production at any time

  Total_Cost : Double = 0.0;
  Active_Grey_Parts : integer = 0;
  AR_Locked : boolean = False; //locks the use of the warehouse
  Conveyor_Busy_until : QWord = 0;  //prevents loading on the main conveyor belt while it's busy

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
    idx_order, i        : integer;
    numb_tasks_total : integer = 0;       // total number of tasks created in "tasks"
    numb_same_task   : integer = 0;

    GreenTasks : array of TTask;
    OtherTasks : array of TTask; //separate green from other tasks, so they can be given priority

begin
  SetLength(GreenTasks, 0);
  SetLength(OtherTasks, 0);

  for idx_order:= 0 to Length(orders)-1 do
  begin
      with current_task do
      begin
        numb_same_task    := 0;

        task_type         := orders[idx_order].order_type;
        part_type         := orders[idx_order].part_type;
        current_operation := Stage_To_Be_Started;
        order_index       := idx_order;

        part_position_AR  := -1;  // to be defined later.   STUDENTS MUST CHANGE

        // Innitialize new variables
        is_grey    := False;
        time_start        := 0;
        time_wait_ar      := 0;

         if( part_type < Part_Lid_Blue )then
        begin
             part_destination  := 1;     // if bases (Exit 1 or Cell 1)
        end else
        begin
            part_destination  := 2;     // if bases (Exit 2 or Cell 2)
        end;

        //Create  orders[idx_order].part_numbers of the same TTask for Dispatcher.

        // numb_tasks_total :=  Length(tasks);
        //SetLength(tasks,  numb_tasks_total + orders[idx_order].part_numbers);
        for numb_same_task := 0 to orders[idx_order].part_numbers-1 do
        begin
          if (part_type = Part_Raw_Green) or (Part_Type = Part_Base_Green) or (Part_Type = Part_Lid_Green) then
          begin
            SetLength(GreenTasks, Length(GreenTasks)+1);
            GreenTasks[high(GreenTasks)] := current_task;
          end
          else
          begin
            SetLength(OtherTasks,Length(OtherTasks)+1);
            OtherTasks[high(OtherTasks)] := current_task;
          end;
        end;
      end;
  end;
  //Join everything in the original array
  SetLength(tasks, Length(GreenTasks) + Length(OtherTasks));
  for i := 0 to High(GreenTasks) do
      tasks[i] := GreenTasks[i];
  for i:= 0 to High(OtherTasks) do
      tasks[Length(greenTasks) + i] := OtherTasks[i];

end;


// Query DB -> Scheduling -> Connect PLC for Dispatching
procedure TFormDispatcher.BStartClick(Sender: TObject);

var
  result: integer;
begin
  if Length(Production_Orders) = 0 then
  begin
    ShowMessage('No orders added yet!');
    Exit;
  end;
 // idx_Task_Executing := 0;
 Total_Cost := 0.0;
 Active_Grey_Parts := 0;
 AR_Locked := False;
 Conveyor_Busy_Until := 0;

  result := M_connect();
  if result = 1 then
    BStart.Caption := 'Connected to PLC'
  else
  begin
    BStart.Caption := 'Start';
    ShowMessage('PLC unavailable. Please try again!');
  end;
end;


procedure TFormDispatcher.FormCreate(Sender: TObject);

var
  i : integer = 0;
begin
  SetLength(ShopTasks, 0);
  idx_Task_Executing := 0;

    // Clear the memo
  Memo_Log.Clear;

  // Set grid to only the header row
  StringGrid1.RowCount := 1;

   // Titles of columns
  StringGrid1.Cells[0, 0] := 'ID';
  StringGrid1.Cells[1, 0] := 'Order Type';
  StringGrid1.Cells[2, 0] := 'Part';
  StringGrid1.Cells[3, 0] := 'Colour';
  StringGrid1.Cells[4, 0] := 'Quantity';
  StringGrid1.Cells[5, 0] := 'Status';

  // Adjust width of columns
  StringGrid1.ColWidths[0] := 80;
  StringGrid1.ColWidths[1] := 100;
  StringGrid1.ColWidths[2] := 100;
  StringGrid1.ColWidths[3] := 100;
  StringGrid1.ColWidths[4] := 80;
  StringGrid1.ColWidths[5] := 100;


  // Initialize monitoring counters
  for i := 1 to 9 do
  begin
    Monitoring_Received[i]     := 0;
    Monitoring_Expedited[i]    := 0;
    Monitoring_InProduction[i] := 0;
  end;

  // Monitoring grid setup (StringGrid2)
  StringGrid2.RowCount := 10;
  StringGrid2.ColCount := 5;
  StringGrid2.Cells[0, 0] := 'Part';
  StringGrid2.Cells[1, 0] := 'In Warehouse';
  StringGrid2.Cells[2, 0] := 'Received';
  StringGrid2.Cells[3, 0] := 'In Production';
  StringGrid2.Cells[4, 0] := 'Expedited';

  StringGrid2.Cells[0, 1] := 'Raw Blue';
  StringGrid2.Cells[0, 2] := 'Raw Green';
  StringGrid2.Cells[0, 3] := 'Raw Grey';
  StringGrid2.Cells[0, 4] := 'Base Blue';
  StringGrid2.Cells[0, 5] := 'Base Green';
  StringGrid2.Cells[0, 6] := 'Base Grey';
  StringGrid2.Cells[0, 7] := 'Lid Blue';
  StringGrid2.Cells[0, 8] := 'Lid Green';
  StringGrid2.Cells[0, 9] := 'Lid Grey';
end;

procedure TFormDispatcher.GroupBox_MonitorClick(Sender: TObject);
begin

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

procedure TFormDispatcher.SpinEdit_Base_BlueChange(Sender: TObject);
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

  if SpinEdit_Raw_Blue.Value + SpinEdit_Raw_Green.Value + SpinEdit_Raw_Gray.Value + SpinEdit_Base_Blue.Value + SpinEdit_Base_Green.Value + SpinEdit_Base_Gray.Value + SpinEdit_Lid_Blue.Value + SpinEdit_Lid_green.Value + SpinEdit_Lid_gray.Value >= 5 then
    begin
  Memo_Log.Append('Error: Too many parts! Maximum is 4.');  //still considering the restriction of only using first column
  Exit;
       end
  else
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
  Memo_Log.Append('Initializing warehouse with ' +
  IntToStr(SpinEdit_Raw_Blue.Value + SpinEdit_Raw_Green.Value + SpinEdit_Raw_Gray.Value +
           SpinEdit_Base_Blue.Value + SpinEdit_Base_Green.Value + SpinEdit_Base_Gray.Value +
           SpinEdit_Lid_Blue.Value + SpinEdit_Lid_green.Value + SpinEdit_Lid_gray.Value)
  + ' part(s).');
  Memo_log.Append('Warehouse successfully innitiated!');
end;



// get the first position (cell) in AR that contains the "Part"
function TFormDispatcher.GET_AR_Position (Part : integer; Warehouse : array of integer): integer;
var
    i : integer;
begin
  result := -1; //if no parts present
  for i := 0 to Length(Warehouse)-1 do
  begin
      if Warehouse[i] = Part then
      begin
          result := i;
          Exit;
      end;
  end;
end;

// Get first free position in first column.
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
    Dispatcher(ShopTasks, ShopResources);
  end;

  UpdateMonitoringGrid;
end;



 (* Global Dispatcher - SIMPLEX, now supporting parallel tasks
procedure TFormDispatcher.Dispatcher(var tasks:TArray_Task; shopfloor: TResources );
var
    i: integer;
    Finished : boolean;
begin
  Finished := True;

    for i := 0 to Length(tasks)-1 do
    begin
      if tasks[i].current_operation <> Stage_Finished then
      begin
        Finished := False;
        if tasks[i].current_operation = Stage_To_Be_Started then
            begin
                // Se for uma peça cinzenta
                if (tasks[i].part_type = Part_Raw_Grey) or (tasks[i].part_type = Part_Base_Grey) or (tasks[i].part_type = Part_Lid_Grey) then
                begin
                   if ActiveGreyParts >= 1 then
                     Continue; // Salta esta tarefa porque já há um cinza ativo. Impede a tarefa de arrancar.

                   tasks[i].is_grey_active := True;
                   Inc(ActiveGreyParts);

      end;
    end;
    Memo_Log.Append('--- Cycle: Task ' + IntToStr(idx+1) + ' of ' + IntToStr(Length(tasks)) + ' ---');
    case tasks[idx].task_type of

      // Expedition
      Type_Expedition :
      begin
        if(idx < Length(tasks)) then
        begin
          Memo_Log.Append('Executing Expedition task...');
          Execute_Expedition_Order(tasks[idx], shopfloor);

          // Next Operation to be executed.
          if(tasks[idx].current_operation = Stage_Finished) then
          begin
            StringGrid1.Cells[5, tasks[idx].order_index + 1] := 'Completed';
            Memo_Log.Append('Expedition Order ' + IntToStr(idx+1) + ' completed.');
            inc(idx_Task_Executing);
          end;
        end;
      end;


      // Production
      Type_Production :
      begin
        if(idx < Length(tasks)) then
                begin
                  Memo_Log.Append('Executing Production task...');
                  Execute_Production_Order(tasks[idx], shopfloor);

                  // Next Operation to be executed.
                  if(tasks[idx].current_operation = Stage_Finished) then
                    begin
                    StringGrid1.Cells[5, tasks[idx].order_index + 1] := 'Completed';
                    Memo_Log.Append('Production Order ' + IntToStr(idx+1) + ' completed.');
                    inc(idx_Task_Executing);
                    end;
                end;
      end;


      // Inbound
      Type_Delivery :
      begin
        if(idx < Length(tasks)) then
                begin
                  Memo_Log.Append('Executing Delivery task...');
                  Execute_Delivery_Order(tasks[idx], shopfloor);

                  // Next Operation to be executed.
                  if(tasks[idx].current_operation = Stage_Finished) then
                    begin
                    StringGrid1.Cells[5, tasks[idx].orEder_index + 1] := 'Completed';
                    Memo_Log.Append('Delivery Order ' + IntToStr(idx+1) + ' completed.');
                    inc(idx_Task_Executing);
                    end;

                end;
      end;


    end;
end;
*)

// Global Dispatcher - SIMPLEX, now supporting parallel tasks
procedure TFormDispatcher.Dispatcher(var tasks:TArray_Task; shopfloor: TResources );
var
  i: integer;
  Finished: Boolean;
  taskTypeName : string;
begin
    Finished := True;

    // Go through every tak in the array
    for i := 0 to Length(tasks) - 1 do
    begin
        if tasks[i].current_operation <> Stage_Finished then
        begin
            Finished := False;

            // Case for grey parts
            if tasks[i].current_operation = Stage_To_Be_Started then
            begin
                if (tasks[i].part_type = Part_Raw_Grey) or (tasks[i].part_type = Part_Base_Grey) or (tasks[i].part_type = Part_Lid_Grey) then
                begin
                   if Active_Grey_Parts >= 1 then
                     Continue; //don't start task

                   tasks[i].is_grey := True;
                   Inc(Active_Grey_Parts);
                end;
            end;

            // Execute a task according to its type
            case tasks[i].task_type of
              Type_Expedition : Execute_Expedition_Order(tasks[i], shopfloor);
              Type_Production : Execute_Production_Order(tasks[i], shopfloor);
              Type_Delivery   : Execute_Delivery_Order(tasks[i], shopfloor);
            end;

            // Check if this task just finished after execution
            if tasks[i].current_operation = Stage_Finished then
            begin
                StringGrid1.Cells[5, tasks[i].order_index + 1] := 'Completed';
                case tasks[i].task_type of
                  Type_Expedition : Memo_Log.Append('Expedition Order ' + IntToStr(i+1) + ' completed.');
                  Type_Production : Memo_Log.Append('Production Order ' + IntToStr(i+1) + ' completed.');
                  Type_Delivery   : Memo_Log.Append('Delivery Order ' + IntToStr(i+1) + ' completed.');
                end;
            end;
        end;
    end;

    // Se varremos todas e todas estão no Stage_Finished:
    if Finished then
    begin
      Memo_Log.Append('All tasks completed!');
      Memo_Log.Append('--- TOTAL COST OF PRODUCTION: ' + FloatToStr(Total_Cost) + ' EUR ---');
      Timer1.Enabled := false;
      SetLength(ShopTasks, 0); // Empty the aray so as not to repeat logs
    end;
end;


// Procedure that executes an expedition order according to SLIDE 19 of T classes.
procedure TFormDispatcher.Execute_Expedition_Order(var task:TTask; shopfloor: TResources );
var
    r : integer;
begin

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
          if(shopfloor.AR_free) and not AR_Locked and (GetTickCount64() > Conveyor_Busy_Until) then  //AR is free
          begin
            Part_Position_AR := GET_AR_Position(Part_Type, WAREHOUSE_Parts);

            if( Part_Position_AR > 0 ) then
            begin
              AR_Locked := True;
              Memo_Log.Append('Looking for part ' + IntToStr(Part_Type) + ' -> found at position ' + IntToStr(Part_Position_AR));
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
          Memo_Log.Append('Unloading part from warehouse position ' + IntToStr(Part_Position_AR));
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
            Memo_Log.Append('Waiting for part ' + IntToStr(Part_Type) + ' on output conveyor...');
            if( r = 1) then                                  // sucess
                Conveyor_Busy_Until := GetTickCount64() + 8000; //prevents a new part from being sent to the conveyor right away, avoising collisions
               AR_Locked := False;
               current_operation :=  Stage_Clear_Pos_AR;
          end;
        end;

        //Updated AR (removing the part from the position)
        Stage_Clear_Pos_AR :
        begin
          SET_AR_Position(Part_Position_AR, 0, WAREHOUSE_Parts);
          inc(Monitoring_Expedited[Part_Type]);
          current_operation :=  Stage_Finished;
        end;

        //Done.
        Stage_Finished :
        begin
          if is_grey then
          begin
            Dec(Active_grey_parts);
            is_grey := False;
          end;
          Total_Cost := Total_Cost + 3.0; // 3€ per expedition task
          current_operation :=  Stage_Finished;
        end;
      end;
  end;
end;


// Procedure that executes a Production order.
procedure TFormDispatcher.Execute_Production_Order(var task:TTask; shopfloor: TResources );
var
    r : integer;
    time_spent: double;
begin

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
          if(shopfloor.AR_free) and not AR_locked and (GetTickCount64() > Conveyor_Busy_Until) then  //AR is free
          begin
            Memo_Log.Append('Looking for raw part at position ' + IntToStr(Part_Position_AR));
            if Part_Destination = 1 then
               Part_Position_AR := GET_AR_Position((Part_Type - 3), WAREHOUSE_Parts)
            else
                Part_Position_AR := GET_AR_Position(Part_Type - 6, WAREHOUSE_Parts); //Raw Part to Get

            if( Part_Position_AR > 0 ) then
            begin
              AR_Locked := True;
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
          Memo_Log.Append('Unloading raw part from warehouse position ' + IntToStr(Part_Position_AR));
          r := M_Unload(Part_Position_AR);

          if ( r = 1 ) then                                 //sucess
             current_operation :=  Stage_Clear_Pos_AR;
        end;


        //Updated AR (removing the part from the position)
        Stage_Clear_Pos_AR :
        begin
          SET_AR_Position(Part_Position_AR, 0, WAREHOUSE_Parts);
          inc(Monitoring_InProduction[Part_Type]);
          current_operation :=  Stage_Production;
        end;

        //Send a part to production
        Stage_Production:
        begin
          if (shopfloor.AR_Out_Part <> 0) and ((shopfloor.AR_Out_Part = (Part_Type - 3)) or (shopfloor.AR_Out_Part = (Part_Type - 6)))  then
          begin
            if Part_Destination = 1 then
              Memo_Log.Append('Producing Base')
            else
              Memo_Log.Append('Producing Lid');

            r := M_Do_Production(Part_Destination);
            Memo_Log.Append('Production result: ' + IntToStr(r) + ' | Destination: ' + IntToStr(Part_Destination) + ' | Part type: ' + IntToStr(part_type));

            if (r = 1) then
               Conveyor_Busy_Until := GetTickCount64() + 8000;
              AR_Locked := False;
              time_start := GetTickCount64();
              current_operation := Stage_Wait;
          end;
        end;

        Stage_Wait:
        begin
        Memo_Log.Append('Waiting for produced part to arrive on input conveyor...');
        if (shopfloor.AR_In_Part = Part_Type) then //task only advances if part type is the correct one
        begin
             time_spent := (GetTickCount64() - time_start) / 1000.0;
            Total_Cost := Total_Cost + (time_spent * 2.0);

            time_wait_ar := GetTickCount64();

          current_operation := Stage_GetPosition;
        end;
      end;


        // Getting a Free Position from the Warehouse
        Stage_GetPosition :
        begin
          if(shopfloor.AR_free) and not AR_Locked and (shopfloor.AR_In_Part = Part_Type) then  //AR is free
          begin
            Part_Position_AR := GET_AR_Free_Position(WAREHOUSE_Parts);
            Memo_Log.append('Position acquired.');
            if( Part_Position_AR > 0 ) then
            begin
               AR_Locked := True;
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
          Memo_Log.Append('Loading produced part into warehouse position ' + IntToStr(Part_Position_AR));
          r := M_Load(Part_Position_AR);

          if ( r = 1 ) then                                 //sucess
             time_spent := (GetTickCount64() - time_wait_ar) / 1000.0;
             Total_Cost := Total_Cost + (time_spent * 6.0);
             current_operation :=  Stage_Update_Pos_AR;
        end;

        //Update the Position in the AR
        Stage_Update_Pos_AR :
        begin
          SET_AR_Position(Part_Position_AR, Part_Type, WAREHOUSE_Parts);
          AR_Locked := False;
          dec(Monitoring_InProduction[Part_Type]);
          current_operation :=  Stage_Finished;
        end;

        //Done.
        Stage_Finished :
        begin
          if is_grey then
          begin
            Dec(Active_Grey_Parts);
            is_grey := False;
          end;
          current_operation :=  Stage_Finished;
        end;
      end;
  end;
end;

// Procedure that executes a Delivery order.
procedure TFormDispatcher.Execute_Delivery_Order(var task:TTask; shopfloor: TResources );
var
    r : integer;
    time_spent: double;
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
               Memo_Log.Append('Free warehouse position found: ' + IntToStr(Part_Position_AR));
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
           Memo_Log.Append('Waiting for part to arrive on input conveyor...');
          if (shopfloor.AR_In_Part = Part_type) then
          begin
          Memo_Log.Append('Part detected on input conveyor. Proceeding to load.');
          time_wait_ar := GetTickCount64();
          current_operation := Stage_GetPosition;
          end;
        end;

         Stage_GetPosition:
        begin
           if (shopfloor.AR_free) and not AR_Locked and (shopfloor.AR_In_Part = Part_Type) then
           begin
              AR_Locked := True;
              current_operation := Stage_Load;
           end;
        end;


        // Wait for part
        Stage_Load:
        begin
              Memo_Log.Append('Loading inbound part into warehouse position ' + IntToStr(Part_Position_AR));
              r := M_Load(Part_Position_AR);

              if (r = 1) then
              begin
              time_spent := (GetTickCount64() - time_wait_ar) / 1000.0;
              Total_Cost := Total_Cost + (time_spent * 6.0);
              current_operation := Stage_Update_Pos_AR_1;
              end;
        end;

        // Update the warehouse position.
        Stage_Update_Pos_AR_1:
        begin
           SET_AR_Position(Part_Position_AR, Part_Type, WAREHOUSE_Parts);
           inc(Monitoring_Received[Part_Type]);
           Memo_Log.Append('Inbound complete. Part ' + IntToStr(Part_Type) + ' stored at warehouse position ' + IntToStr(Part_Position_AR));
           AR_Locked := False;
           current_operation := Stage_Finished;
        end;

        Stage_Finished:
        begin
             if Part_Type = Part_Raw_Green then
             Total_Cost := Total_Cost + 4.0
           else if (Part_Type = Part_Raw_Blue) or (Part_Type = Part_Raw_Grey) then
             Total_Cost := Total_Cost + 1.0;

             if is_grey then
           begin
             Dec(Active_Grey_Parts);
             is_grey := False;
           end;

           current_operation := Stage_Finished;
        end;

     end;
  end;
end;

procedure TFormDispatcher.Button_Add_OrderClick(Sender: TObject);
var
  newRow: integer;
  new_order: TProduction_Order;
begin
  // Validate
  if (ComboBox1.Text = 'Select') or (ComboBox2.Text = 'Select') or
     (ComboBox3.Text = 'Select') or (SpinEdit_Quantity.Value = 0) then
  begin
    ShowMessage('Please fill all fields before adding an order.');
    Exit;
  end;

  // Order type
  if ComboBox1.Text = 'Expedition' then
    new_order.order_type := Type_Expedition
  else if ComboBox1.Text = 'Inbound' then
    new_order.order_type := Type_Delivery
  else if ComboBox1.Text = 'Production' then
    new_order.order_type := Type_Production;

  // Quantity
  new_order.part_numbers := SpinEdit_Quantity.Value;

  // Part type
  if (ComboBox2.Text = 'Raw Material') and (ComboBox3.Text = 'Blue') then
    new_order.part_type := Part_Raw_Blue
  else if (ComboBox2.Text = 'Raw Material') and (ComboBox3.Text = 'Green') then
    new_order.part_type := Part_Raw_Green
  else if (ComboBox2.Text = 'Raw Material') and (ComboBox3.Text = 'Grey') then
    new_order.part_type := Part_Raw_Grey
  else if (ComboBox2.Text = 'Base') and (ComboBox3.Text = 'Blue') then
    new_order.part_type := Part_Base_Blue
  else if (ComboBox2.Text = 'Base') and (ComboBox3.Text = 'Green') then
    new_order.part_type := Part_Base_Green
  else if (ComboBox2.Text = 'Base') and (ComboBox3.Text = 'Grey') then
    new_order.part_type := Part_Base_Grey
  else if (ComboBox2.Text = 'Lid') and (ComboBox3.Text = 'Blue') then
    new_order.part_type := Part_Lid_Blue
  else if (ComboBox2.Text = 'Lid') and (ComboBox3.Text = 'Green') then
    new_order.part_type := Part_Lid_Green
  else if (ComboBox2.Text = 'Lid') and (ComboBox3.Text = 'Grey') then
    new_order.part_type := Part_Lid_Grey;

    if new_order.part_type = 0 then
  begin
    ShowMessage('Invalid part/colour combination!');
    Exit;
  end;

  // Add to the Production_Orders array
  SetLength(Production_Orders, Length(Production_Orders) + 1);
  Production_Orders[High(Production_Orders)] := new_order;

  // Grid, for display
  newRow := StringGrid1.RowCount;
  StringGrid1.RowCount := newRow + 1;
  StringGrid1.Cells[0, newRow] := IntToStr(newRow);
  StringGrid1.Cells[1, newRow] := ComboBox1.Text;
  StringGrid1.Cells[2, newRow] := ComboBox2.Text;
  StringGrid1.Cells[3, newRow] := ComboBox3.Text;
  StringGrid1.Cells[4, newRow] := IntToStr(SpinEdit_Quantity.Value);
  StringGrid1.Cells[5, newRow] := 'Pending';
end;

procedure TFormDispatcher.UpdateMonitoringGrid;
var
  p, i, count: integer;
begin
  for p := 1 to 9 do
  begin

    count := 0;
    for i := 1 to Length(WAREHOUSE_Parts)-1 do
      if WAREHOUSE_Parts[i] = p then inc(count);

    StringGrid2.Cells[1, p] := IntToStr(count);
    StringGrid2.Cells[2, p] := IntToStr(Monitoring_Received[p]);
    StringGrid2.Cells[3, p] := IntToStr(Monitoring_InProduction[p]);
    StringGrid2.Cells[4, p] := IntToStr(Monitoring_Expedited[p]);
  end;
end;


end.

