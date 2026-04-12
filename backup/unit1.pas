unit Unit1;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  Grids;

type

  { TFormQuality }

  TFormQuality = class(TForm)
    BtSave: TButton;
    GroupBoxQuality: TGroupBox;
    GroupBoxCost: TGroupBox;
    GridQuality: TStringGrid;
    GridStats: TStringGrid;
    procedure BtSaveClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure GroupBoxQualityClick(Sender: TObject);
    procedure FormShow(Sender: TObject);
  private
    procedure LoadProductionData;
    procedure StatGridConfig;
    procedure UpdateStats(DefectCost: Double);
  public

  end;

var
  FormQuality: TFormQuality;

implementation

uses unitdispatcher;

{$R *.lfm}

{ TFormQuality }

procedure TFormQuality.FormCreate(Sender: TObject);
begin

end;


procedure TFormQuality.GroupBoxQualityClick(Sender: TObject);
begin

end;

procedure TFormQuality.FormShow(Sender: TObject);
begin
  LoadProductionData;
  StatGridConfig;
  UpdateStats(0.0);
end;

procedure TFormQuality.StatGridConfig;
begin
  GridStats.RowCount := 6;
  GridStats.ColCount := 2;


  GridStats.ColWidths[0] := 200;
  GridStats.ColWidths[1] := 100;

  GridStats.Cells[0, 0] := 'Stat';
  GridStats.Cells[1, 0] := 'Value';

  GridStats.Cells[0, 1] := 'Uptime Cell 1';
  GridStats.Cells[0, 2] := 'Uptime Cell 2';
  GridStats.Cells[0, 3] := 'Average AR wait';
  GridStats.Cells[0, 4] := 'Cost of Defects';
  GridStats.Cells[0, 5] := 'Total Cost';
end;

procedure TFormQuality.UpdateStats(DefectCost: Double);
begin
  GridStats.Cells[1, 1] := FormatFloat('0.00', Total_Uptime_Cell1) + ' s';
  GridStats.Cells[1, 2] := FormatFloat('0.00', Total_Uptime_Cell2) + ' s';
  GridStats.Cells[1, 3] := FormatFloat('0.00', Avg_AR_Wait) + ' s';
  GridStats.Cells[1, 4] := FormatFloat('0.00', DefectCost) + ' EUR';
  GridStats.Cells[1, 5] := FormatFloat('0.00', Total_Cost + DefectCost) + ' EUR';
end;

function GetPartName(ID: integer): string;
begin
  case ID of
    Part_Base_Blue:  Result := 'Base Blue';
    Part_Base_Green: Result := 'Base Green';
    Part_Base_Grey:  Result := 'Base Grey';
    Part_Lid_Blue:   Result := 'Lid Blue';
    Part_Lid_Green:  Result := 'Lid Green';
    Part_Lid_Grey:   Result := 'Lid Grey';
    else Result := 'Unknown Part';
  end;
end;

procedure TFormQuality.LoadProductionData;
var
  i, j, rowCount: integer;
  partName: string;
begin
  GridQuality.RowCount := 1;
  GridQuality.Cells[0, 0] := 'Order ID';
  GridQuality.Cells[1, 0] := 'Part Type';
  GridQuality.Cells[2, 0] := 'Defect?';

  rowCount := 1;
  for i := 0 to High(Production_Orders) do
  begin

    if Production_Orders[i].order_type <> Type_Production then
      Continue;

    partName := GetPartName(Production_Orders[i].part_type);

    for j := 1 to Production_Orders[i].part_numbers do
    begin
      GridQuality.RowCount := rowCount + 1;
      GridQuality.Cells[0, rowCount] := IntToStr(i);
      GridQuality.Cells[1, rowCount] := partName;
      GridQuality.Cells[2, rowCount] := '0';
      Inc(rowCount);
    end;
  end;
end;

procedure TFormQuality.BtSaveClick(Sender: TObject);
var
  r, orderIdx: integer;
  isDefect: boolean;
begin
  SetLength(Production_Orders_Good_Quality, Length(Production_Orders));

  for r := 0 to High(Production_Orders_Good_Quality) do
  begin
    Production_Orders_Good_Quality[r] := Production_Orders[r];
    Production_Orders_Good_Quality[r].part_numbers := 0;
  end;

  Total_Defect_Cost := 0;

  for r := 1 to GridQuality.RowCount - 1 do
  begin
    orderIdx := StrToInt(GridQuality.Cells[0, r]);
    isDefect := GridQuality.Cells[2, r] = '1';

    if isDefect then
       Total_Defect_Cost := Total_Defect_Cost + 5.0
    else
       Inc(Production_Orders_Good_Quality[orderIdx].part_numbers);
  end;

  UpdateStats(Total_Defect_Cost);

  ShowMessage('Production plan successfully validated!');

end;
end.

