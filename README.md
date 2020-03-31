## Usage

bm.sh [ options ]

### Options:
-s <<Width>x<Height>>      ( Size of grid in cells: 3x3..26x26 )\
-p <<PromptLevel>> 0,1,2,3 ( Increasing verbosity )\
-h show Help\
-r "Reveal" mode (for debug, etc.)
  
### Defaults
<Mode>        : Normal
<Size>        : 9x9
<PromptLevel> : 3

## General

A grid of "covered" cells is displayed, some of which contain bombs (mines),
"covered" means one cannot tell where bombs are positioned.

* Game object is to "Clear" (Dig) all cells which do not contain a bomb.

* Or, conversley, you can "Mark" every Mine, by deduction.

* If a cell containing a bomb is uncovered "Dug", game is over.

* When an unmined "Clear" cell is "Dug", for each neighbor cell,
  a number is revealed, indicating count of mined cells.

## Cell Addresses

  Each grid cell has a unique address represented
  by a Row (letter) and Column (number).

  Example: Top-Left Cell = A1


## Game Actions

  This game is played at your "console" command prompt by entering
    a cell address immeditely followed by an optional action
    specifier.
    
  If action specifier is absent a default action of
    "Dig" is assumed.

  The actions you can perform are represented by letters 'D','M','U'.
  
###  Action Specifier Meaning

    D) Dig
    M) Mark
    U) UnMark

* 'D'igging a covered cell reveals neighbor bomb count or
    reveals a bomb cell (Game Over)
   
* 'M'arking a covered cell marks it as a suspected bomb by
    placing a 'M' flag on the cell.

* 'U'nmarking a Marked cell removes a previous mark,
    in case an error in marking is discovered.

### Cell Address Expressions

  For conveinience, multiple address expressions may be
  used to apply an action to mulitiple cell ranges. Note:
  cell range expressions contain '-' between start and end.

  Example: A1-C3D C6-7M

  This would Dig at Cells A1,A2,A3,B1,B2,B3,C1,C2,C3 and
  Mark cells C6 and C7.
  ( Last letter specifies action for each range expression )

###  Address expression forms
  
    <Row><Col>-<Row><Col>   ( Ex. A2-C4 )
    <Row><Col>-<Col>        ( Ex. A2-5  )
    <Row><Col>-<Row>        ( Ex. A1-J  )
    <Row>-<Row><Col>        ( Ex. B-D6  )
    <Row><Col>              ( Ex. A1    )



# Details

    * The first cell opened is never a bomb.
    * Digging a cell with no neighboring mines automatically uncovers obviously safe neighbor cells.
    * Side cells and corner cells have fewer neighbors since grid edges do not "wrap around".
    * Incorrect bomb markings dont kill, but can lead to mistakes which do.
    * Win by Marking all bombs correctly or, by clearing (Digging) all non-bomb cells.
    * An incorrectly Marked cell will have to corrected to win.

# Status Information

    * Upper left corner  : Number of turns taken
    * Below upper left   : Elapsed time (updated after turns)
    * Upper right corner : Number of covered cells left
    * Below upper right  : Number of "mined" cells 

                                                                            
