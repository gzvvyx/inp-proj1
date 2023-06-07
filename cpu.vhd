-- cpu.vhd: Simple 8-bit CPU (BrainFuck interpreter)
-- Copyright (C) 2022 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): Andrej Nespor <xnespo10@stud.fit.vutbr.cz>
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- ----------------------------------------------------------------------------
--                        Entity declaration
-- ----------------------------------------------------------------------------
entity cpu is
 port (
   CLK   : in std_logic;  -- hodinovy signal
   RESET : in std_logic;  -- asynchronni reset procesoru
   EN    : in std_logic;  -- povoleni cinnosti procesoru
 
   -- synchronni pamet RAM
   DATA_ADDR  : out std_logic_vector(12 downto 0); -- adresa do pameti
   DATA_WDATA : out std_logic_vector(7 downto 0); -- mem[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
   DATA_RDATA : in std_logic_vector(7 downto 0);  -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
   DATA_RDWR  : out std_logic;                    -- cteni (0) / zapis (1)
   DATA_EN    : out std_logic;                    -- povoleni cinnosti
   
   -- vstupni port
   IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA <- stav klavesnice pokud IN_VLD='1' a IN_REQ='1'
   IN_VLD    : in std_logic;                      -- data platna
   IN_REQ    : out std_logic;                     -- pozadavek na vstup data
   
   -- vystupni port
   OUT_DATA : out  std_logic_vector(7 downto 0);  -- zapisovana data
   OUT_BUSY : in std_logic;                       -- LCD je zaneprazdnen (1), nelze zapisovat
   OUT_WE   : out std_logic                       -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'
 );
end cpu;


-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
architecture behavioral of cpu is

  signal PC : std_logic_vector(12 downto 0) := (others=>'0'); --13bits (bcs of DATA_ADDR)
  signal PC_inc : std_logic; --inc flag
  signal PC_dec : std_logic; --dec flag

  signal PTR : std_logic_vector(12 downto 0) := (12=>'1', others=>'0'); --13bits (bcs of DATA_ADDR)
  signal PTR_inc : std_logic; --inc flag
  signal PTR_dec : std_logic; --dec flag

  signal CNT : std_logic_vector(7 downto 0) := (others=>'0'); --4bits
  signal CNT_inc : std_logic; --inc flag
  signal CNT_dec : std_logic; --dec flag
  signal CNT_set : std_logic; --set falg

  signal MX1_sel : std_logic;
  signal MX1_out : std_logic_vector(12 downto 0) := (others=>'0'); --13bits

  signal MX2_sel : std_logic_vector(1 downto 0) := (others=>'0'); --2bits (0, 1, 2)
  signal MX2_out : std_logic_vector(7 downto 0) := (others=>'0'); --8bits


type FSMstates is (
  S_IDLE, --init state
  S_FETCH, --get input
  S_GET_INST, --get instruction
  --instruction states
  S_PTR_INC, -- >
  S_PTR_DEC, -- <
  --
  S_CELL_INC, --read +
  S_CELL_INC_w, --write +
  S_CELL_DEC, --read -
  S_CELL_DEC_w, --write -

  S_WHILE_START,
  S_WHILE_START_check1,
  S_WHILE_skip,
  S_WHILE_START_check2,

  S_WHILE_END,
  S_WHILE_END_check1,
  S_WHILE_rollback,
  S_WHILE_END_check2,
  S_WHILE_END_check3,

  S_DO_WHILE_START,
  S_DO_WHILE_START_check,

  S_DO_WHILE_END,
  S_DO_WHILE_END_check1,
  S_DO_WHILE_rollback,
  S_DO_WHILE_END_check2,
  S_DO_WHILE_END_check3,

  S_WRITE, -- set up .
  S_WRITE_w, -- .
  S_READ, -- set up ,
  S_READ_w, -- ,
  --
  S_OTHER, --comment, most likely
  S_END
);
signal current_state : FSMstates;
signal next_state : FSMstates;

begin

-- ----------------------------------------------------------------------------
--                      PC register counter
-- ----------------------------------------------------------------------------
pc_cnt : process(CLK, RESET)
begin
  if RESET = '1' then
    PC <= (others=>'0');
  elsif rising_edge(CLK) then
    if PC_inc = '1' then --flag = 1 --> increment PC
      PC <= PC + 1;
    end if ;
    if PC_dec = '1' then --flag = 1 --> decrement PC
      PC <= PC - 1;
    end if ;
  end if ;
end process pc_cnt;

-- ----------------------------------------------------------------------------
--                      PTR register counter
-- ----------------------------------------------------------------------------
ptr_cnt : process(CLK, RESET)
begin
  if RESET = '1' then
    PTR <= (12=>'1', others=>'0');
  elsif rising_edge(CLK) then
    if PTR_inc = '1' then --flag = 1 --> increment PTR
      PTR <= PTR + 1;
    end if ;
    if PTR_dec = '1' then --flag = 1 --> decrement PTR
      PTR <= PTR - 1;
    end if ;
  end if ;
end process ptr_cnt;

-- ----------------------------------------------------------------------------
--                      CNT register counter
-- ----------------------------------------------------------------------------
cnt_cnt : process(CLK, RESET)
begin
  if RESET = '1' then
    CNT <= (others=>'0');
  elsif rising_edge(CLK) then
    if CNT_inc = '1' then --flag = 1 --> increment CNT
      CNT <= CNT + 1;
    end if ;
    if CNT_dec = '1' then --flag = 1 --> decrement CNT
      CNT <= CNT - 1;
    end if ;
    if CNT_set = '1' then
      CNT <= (0=>'1', others=>'0'); --set CNT to 1
    end if ;
  end if ;
end process cnt_cnt;

-- ----------------------------------------------------------------------------
--                      MultipleXor 1
-- ----------------------------------------------------------------------------
mx1 : process(PC, PTR, MX1_sel)
begin
  if MX1_sel = '0' then
    MX1_out <= PC;
  elsif MX1_sel = '1' then
    MX1_out <= PTR;
  else
    MX1_out <= (others => '0');
  end if;
end process mx1;
DATA_ADDR <= MX1_out;

-- ----------------------------------------------------------------------------
--                      MultipleXor 2
-- ----------------------------------------------------------------------------
mx2 : process(MX2_sel, IN_DATA, DATA_RDATA)
begin
  if MX2_sel = "00" then
    MX2_out <= IN_DATA;
  elsif MX2_sel = "01" then
    MX2_out <= DATA_RDATA - 1;
  elsif MX2_sel = "10" then
    MX2_out <= DATA_RDATA + 1;
  else 
    MX2_out <= (others => '0');
  end if ;
end process mx2;
DATA_WDATA <= MX2_out;

-- ----------------------------------------------------------------------------
--                      FSM current sate logic
-- ----------------------------------------------------------------------------
FSM_current_state : process (CLK, RESET)
begin
  if RESET = '1' then
    current_state <= S_IDLE;
  elsif rising_edge(CLK) then
    if EN = '1' then
      current_state <= next_state;
    end if;
  end if;
end process FSM_current_state;

-- ----------------------------------------------------------------------------
--                      FSM next state/output logic
-- ----------------------------------------------------------------------------
FSM : process (current_state, DATA_RDATA, IN_VLD, OUT_BUSY, CNT)
begin
  --INIT
--ram
  DATA_EN <= '0';
  DATA_RDWR <= '0';
--in
  IN_REQ <= '0';
--out
  OUT_WE <= '0';
  OUT_DATA <= (others=>'0');
--own signals
  PC_inc <= '0';
  PC_dec <= '0';
  PTR_inc <= '0';
  PTR_dec <= '0';
  CNT_inc <= '0';
  CNT_dec <= '0';
  CNT_set <= '0';
  MX1_sel <= '0';
  MX2_sel <= "00";


  case current_state is

    when S_IDLE =>
      next_state <= S_FETCH;

-- ----------------------------------------------------------------------------

    when S_FETCH =>
      next_state <= S_GET_INST;
      DATA_EN <= '1';

-- ----------------------------------------------------------------------------

    when S_GET_INST =>
      case DATA_RDATA is
        when x"3E" => next_state <= S_PTR_INC;
        when x"3C" => next_state <= S_PTR_DEC;
        when x"2B" => next_state <= S_CELL_INC;
        when x"2D" => next_state <= S_CELL_DEC;
        when x"5B" => next_state <= S_WHILE_START;
        when x"5D" => next_state <= S_WHILE_END;
        when x"28" => next_state <= S_DO_WHILE_START;
        when x"29" => next_state <= S_DO_WHILE_END;
        when x"2E" => next_state <= S_WRITE;
        when x"2C" => next_state <= S_READ;
        when x"00" => next_state <= S_END;
        when others => next_state <= S_OTHER;
      end case;
-- ----------------------------------------------------------------------------

      when S_PTR_INC => next_state <= S_FETCH;
        PTR_inc <= '1'; -- >
        PC_inc <= '1'; --

-- ----------------------------------------------------------------------------

      when S_PTR_DEC => next_state <= S_FETCH;
        PTR_dec <= '1'; -- <
        PC_inc <= '1'; --

-- ----------------------------------------------------------------------------

      when S_CELL_INC => next_state <= S_CELL_INC_w;
        DATA_EN <= '1';
        MX1_sel <= '1'; -- mx1 out PTR

      when S_CELL_INC_w => next_state <= S_FETCH;
        DATA_EN <= '1';  
        MX2_sel <= "10"; -- RDATA-1
        MX1_sel <= '1'; -- mx1 out PTR
        DATA_RDWR <= '1'; -- write
        PC_inc <= '1'; 

-- ----------------------------------------------------------------------------

      when S_CELL_DEC => next_state <= S_CELL_DEC_w;
        DATA_EN <= '1';
        MX1_sel <= '1'; -- mx1 out PRT

      when S_CELL_DEC_w => next_state <= S_FETCH;
        DATA_EN <= '1';
        MX2_sel <= "01"; -- RDATA+1
        MX1_sel <= '1'; -- mx1 out PTR
        DATA_RDWR <= '1'; -- write
        PC_inc <= '1';

-- ----------------------------------------------------------------------------

      when S_WRITE => next_state <= S_WRITE_w;
        DATA_EN <= '1';
        MX1_sel <= '1';
      
      when S_WRITE_w =>
        if OUT_BUSY = '1' then
          next_state <= S_WRITE_w; -- repeat until not busy
          DATA_EN <= '1';
          MX1_sel <= '1';
        elsif OUT_BUSY = '0' then
          next_state <= S_FETCH;
          OUT_DATA <= DATA_RDATA;
          OUT_WE <= '1';
          PC_inc <= '1';
        end if ;

-- ----------------------------------------------------------------------------

      when S_READ => next_state <= S_READ_w;
          IN_REQ <= '1';

      when S_READ_w =>
        if IN_VLD = '0' then
          next_state <= S_READ_w; -- repeat until valid
          IN_REQ <= '1'; -- ask for valid
        elsif IN_VLD = '1' then
          next_state <= S_FETCH;
          DATA_EN <= '1';
          DATA_RDWR <= '1';
          MX1_sel <= '1';
          MX2_sel <= "00";
          PC_inc <= '1';
        end if ;

-- ----------------------------------------------------------------------------

      when S_WHILE_START => next_state <= S_WHILE_START_check1;
        DATA_EN <= '1';
        MX1_sel <= '1';
        PC_inc <= '1';
      
      when S_WHILE_START_check1 =>
        if DATA_RDATA = x"00" then
          next_state <= S_WHILE_skip; -- skip while
          CNT_set <= '1';
          DATA_EN <= '1';
        else
          next_state <= S_FETCH;
        end if ;
      
      when S_WHILE_skip =>
        if CNT /= x"00" then
          next_state <= S_WHILE_START_check2;
          DATA_EN <= '1';
        else
          next_state <= S_FETCH;
        end if ;

      when S_WHILE_START_check2 => next_state <= S_WHILE_skip;
        if DATA_RDATA = x"5B" then -- [
          CNT_inc <= '1';
        elsif DATA_RDATA = x"5D" then -- ]
          CNT_dec <= '1';
        end if ;
        PC_inc <= '1';

-- ----------------------------------------------------------------------------

      when S_WHILE_END => next_state <= S_WHILE_END_check1;
        DATA_EN <= '1';
        MX1_sel <= '1';
      
      when S_WHILE_END_check1 =>
        if DATA_RDATA = x"00" then
          next_state <= S_FETCH;
          PC_inc <= '1';
        else
          next_state <= S_WHILE_END_check2;
          CNT_set <= '1';
          PC_dec <= '1';
          DATA_EN <= '1';
        end if ;
      
      when S_WHILE_END_check2 =>
        if CNT /= x"00" then
          next_state <= S_WHILE_rollback;
          DATA_EN <= '1';
        else
          next_state <= S_FETCH;
        end if ;

      when S_WHILE_rollback => next_state <= S_WHILE_END_check3;
          if DATA_RDATA = x"5D" then -- ]
            CNT_inc <= '1';
          elsif DATA_RDATA = x"5B" then -- [
            CNT_dec <= '1';
          end if ;

      when S_WHILE_END_check3 => next_state <= S_WHILE_END_check2;
        if CNT = x"00" then
          PC_inc <= '1';
        else
          PC_dec <= '1';
        end if ;

-- ----------------------------------------------------------------------------

      when S_DO_WHILE_START => next_state <= S_DO_WHILE_START_check;
        DATA_EN <= '1';
        MX1_sel <= '1';
        PC_inc <= '1';
      
      when S_DO_WHILE_START_check => next_state <= S_FETCH;

-- ---------------------------------------------------------------------------

      when S_DO_WHILE_END => next_state <= S_DO_WHILE_END_check1;
        DATA_EN <= '1';
        MX1_sel <= '1';
      
      when S_DO_WHILE_END_check1 =>
        if DATA_RDATA = x"00" then
          next_state <= S_FETCH;
          PC_inc <= '1';
        else
          next_state <= S_DO_WHILE_END_check2;
          CNT_set <= '1';
          PC_dec <= '1';
        end if ;
      
      when S_DO_WHILE_END_check2 =>
        if CNT = x"00" then
          next_state <= S_FETCH;
        else
          next_state <= S_DO_WHILE_rollback;
          DATA_EN <= '1';
        end if ;

      when S_DO_WHILE_rollback => next_state <= S_DO_WHILE_END_check3;
        if DATA_RDATA = x"29" then -- )
          CNT_inc <= '1';
        elsif DATA_RDATA = x"28" then -- (
          CNT_dec <= '1';
        end if ;

      when S_DO_WHILE_END_check3 => next_state <= S_DO_WHILE_END_check2;
        if CNT = x"00" then
          PC_inc <= '1';
        else
          PC_dec <= '1';
        end if ;

-- ----------------------------------------------------------------------------

      when S_OTHER => next_state <= S_IDLE;
        PC_inc <= '1';

-- ----------------------------------------------------------------------------

      when S_END => next_state <= S_END;
    when others => next_state <= S_IDLE;
  end case;
end process;

end behavioral;

