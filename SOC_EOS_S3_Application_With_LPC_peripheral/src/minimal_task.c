#include "Fw_global_config.h"   // This defines application specific charactersitics

#include <stdio.h>
#include "FreeRTOS.h"
#include "task.h"
#include "semphr.h"
#include "timers.h"
#include "RtosTask.h"

#include "minimal_task.h"

xQueueHandle xQH_timerctrl0_mon;
xTaskHandle xTH_timerctrl0_mon;


void minimal_taskfunc_timerctrl0_mon(void *pvParameters) 
{
    uint8_t msg;
    portBASE_TYPE status;

    uint32_t maskAddress = 0xffff000;
    uint32_t maskData = 0xff0;
    uint32_t maskCycleType = 0xf;

    while(1)
    {
        status = xQueueReceive(xQH_timerctrl0_mon, &msg, portMAX_DELAY);

        if (status == pdTRUE)
        {
            switch(msg)
            {
                case TIMERCTRL0_ENABLED:
                    dbg_str("\ntimer0 enabled\n");
                    break;

                case TIMERCTRL0_ISR:
                    dbg_str("\nTPM cycle detected - interrupt from FPGA occured.\n");

					uint32_t register0 = hal_fpga_onion_breath_getval_reg (22);	//LPC cycle data (now in one register)

					uint32_t cycleAdress = register0 & maskAddress;
					cycleAdress >>= 12;

					uint32_t cycleData = register0 & maskData;
					cycleData >>= 4;

					uint32_t cycleType = register0 & maskCycleType;

					dbg_str("\n\n");
					dbg_str_hex32("LPC cycle address: ", cycleAdress);
					dbg_str("\n\n");
					dbg_str_hex32("LPC cycle data: ", cycleData);
					dbg_str("\n\n");
					if (cycleType > 0UL) dbg_str_hex32("This is write cycle\n");
					else dbg_str_hex32("This is read cycle\n");
                    break;

                case TIMERCTRL0_DISABLED:
                    dbg_str("\ntimer0 disabled\n");
                    break;

                default:
                    dbg_str("unknown");
                    break;    
            }
        }
    }
}


void minimal_task_init_timerctrl0_mon()
{
    // create task
    xTaskCreate(minimal_taskfunc_timerctrl0_mon, 
                "tmr0mon", 
                configMINIMAL_STACK_SIZE, 
                (void *)NULL,
                tskIDLE_PRIORITY + 2UL, 
                &xTH_timerctrl0_mon);

    // create queue
    xQH_timerctrl0_mon = xQueueCreate(10, sizeof(uint8_t));
}

void minimal_task_sendmsg_timerctrl0_mon(uint8_t msg)
{
    xQueueSendToBack(xQH_timerctrl0_mon, &msg, 0);
}

void minimal_task_sendmsgFromISR_timerctrl0_mon(uint8_t msg)
{
    BaseType_t xHigherPriorityTaskWoken;
    xHigherPriorityTaskWoken = pdFALSE;

    xQueueSendFromISR(xQH_timerctrl0_mon, &msg, &xHigherPriorityTaskWoken);

    portYIELD_FROM_ISR( xHigherPriorityTaskWoken );
}
