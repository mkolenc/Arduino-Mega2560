/* pulse-width_modulation.c
 * 
 * Max Kolenc
 * Spring 2024
 */

#define __DELAY_BACKWARD_COMPATIBLE__ 1
#define F_CPU 16000000UL

#include <avr/io.h>
#include <avr/interrupt.h>
#include <util/delay.h>
#include <stdbool.h>

#define SOS_SIGNAL_LEN 19
#define SHOW_SIGNAL_LEN 43
#define NUM_LEDS 4

#define DELAY1 0.000001
#define DELAY3 0.01

#define PRESCALE_DIV1 8
#define PRESCALE_DIV3 64
#define TOP1 ((int)(0.5 + (F_CPU/PRESCALE_DIV1*DELAY1))) 
#define TOP3 ((int)(0.5 + (F_CPU/PRESCALE_DIV3*DELAY3)))

#define PWM_PERIOD ((long int)500)

volatile long int count = 0;
volatile long int slow_count = 0;

ISR(TIMER1_COMPA_vect) {
	count++;
}

ISR(TIMER3_COMPA_vect) {
	slow_count += 5;
}

/* *********************************************
 * ********* BEGINNING OF CODE SECTION *********
 * *********************************************
 */

 /*
 *  Purpose: Turn an LED on or off.
 *
 *  Parameters:
 *    - LED: The number of the LED to turn on (0, 1, 2 or 3).
 *    - is_led_on: Whether to turn the led 'on' (true) or 'off' (false).
 * 
 *  Returns:
 *    - void: Nothing.
 */
void led_state(uint8_t LED, bool is_led_on)
{
	if (LED > NUM_LEDS - 1)
        return;

    // Bit patterns corresponding to each LED
    static const uint8_t LED_bits[NUM_LEDS] = {0x80, 0x20, 0x08, 0x02};

	DDRL = 0xFF;
	if (is_led_on)
		PORTL |= LED_bits[LED];
	else
		PORTL &= ~LED_bits[LED];
}

/*
 *  Purpose: Display an SOS signal with the LED's
 *
 *  Parameters:
 *    - void: Nothing.
 *
 *  Returns:
 *    - void: Nothing.
 */
void SOS(void)
{
	// Format: {led_pattern, duration}
	static const uint16_t sos_signal[SOS_SIGNAL_LEN][2] = {
		{0X1, 100}, {0, 250}, {0X1, 100}, {0, 250}, {0X1, 100}, {0, 500},
		{0XF, 250}, {0, 250}, {0XF, 250}, {0, 250}, {0XF, 250}, {0, 500},
		{0X1, 100}, {0, 250}, {0X1, 100}, {0, 250}, {0X1, 100}, {0, 250},
		{0, 250}
	};

	for (uint8_t i = 0; i < SOS_SIGNAL_LEN; ++i) {
		for (uint8_t led = 0, mask = 1; led < NUM_LEDS; ++led, mask <<= 1) {
			led_state(led, sos_signal[i][0] & mask);
		}
		_delay_ms(sos_signal[i][1]);
	}
}

/*
 *  Purpose: Private helper function to turn an LED 'on' or 'off' based on its
 *           pulse-width modulation threshold. Note, this needs to be called continuously
 *           to take effect. It is implemented here to avoid code duplication in glow and pulse_glow.
 *
 *  Parameters:
 *    - LED: The number of the LED (0, 1, 2 or 3).
 *    - threshold: The number of ms to have the LED on. 
 *                 This should be between [0 - PWM_PERIOD] inclusive.
 *    - is_led_on: A pointer to the state of the LED. True for 'on', false for 'off'.
 *
 *  Returns:
 *    - void: Nothing.
 */
inline void apply_pulse_width_modulation(const uint8_t LED, const long threshold, bool* is_led_on)
{
	if (count < threshold) {
		if (!(*is_led_on)) {
			*is_led_on = true;
			led_state(LED, *is_led_on);
		}
	} else if (count < PWM_PERIOD) {
		if (*is_led_on) {
			*is_led_on = false;
			led_state(LED, *is_led_on);
		}
	} else
		count = 0L;
}

/*
 *  Purpose: Get a single LED to 'glow' using  pulse-width modulation.
 *           This is done INFINITLY!
 *
 *  Parameters:
 *    - LED: The number of the LED to turn on (0, 1, 2 or 3).
 *    - brightness: The duty cycle (percentage of period 'on) of our LED. 
 *                  This value should be between 0.0 - 1.0 inclusive.
 *
 *  Returns:
 *    - void: Nothing.
 */
void glow(uint8_t LED, float brightness)
{
	if (brightness < 0.0 || brightness > 1.0)
		return;

	const long threshold = PWM_PERIOD * brightness; 
	bool is_led_on = false;

	while (true)
		apply_pulse_width_modulation(LED, threshold, &is_led_on);
}

/*
 *  Purpose: Get a single LED to pulse from dim to bright using pulse-width modulation.
 *           This is done INFINITLY!
 *
 *  Parameters:
 *    - LED: The number of the LED to turn on (0, 1, 2 or 3).
 *
 *  Returns:
 *    - void: Nothing.
 */
void pulse_glow(uint8_t LED)
{
	const long PULSE_RATE = 2 * 5; // 2 * DELAY3 (20 milliseconds).
	long threshold = 0L;
	long delta_threshold = 0L;
	bool is_led_on = false;

	while (true) {
		apply_pulse_width_modulation(LED, threshold, &is_led_on);

		// Change the threshold every (20 milliseconds).
		if (slow_count < PULSE_RATE)
			continue;
			
		if (delta_threshold > 0)
			delta_threshold = threshold < PWM_PERIOD ? 1 : -1;
		else
			delta_threshold = threshold > 0 ? -1 : 1;
		
		threshold += delta_threshold;
		slow_count = 0;
	}
}

/*
 *  Purpose: Sick light display, intro to crazy frog song!
 *
 *  Parameters:
 *    - void: Nothing.
 *
 *  Returns:
 *    - void: Nothing.
 */
void light_show(void)
{
	// Format: {led_pattern, duration}
	static const uint8_t show_signal[SHOW_SIGNAL_LEN][2] = {
		{0XF, 250}, {0X0, 250}, {0XF, 250}, {0X0, 250}, {0XF, 250}, {0X0, 250},
		{0X6, 100}, {0X0, 100}, {0X9, 100}, {0X0, 100}, {0XF, 250}, {0X0, 250},
		{0XF, 250}, {0X0, 250}, {0XF, 250}, {0X0, 250}, {0X9, 100}, {0X0, 100},
		{0X6, 100}, {0X0, 100}, {0X8, 100}, {0XC, 100}, {0X6, 100}, {0X3, 100},
		{0X1, 100}, {0X3, 100}, {0X6, 100}, {0XC, 100}, {0X8, 100}, {0XC, 100},
		{0X6, 100}, {0X3, 100}, {0X1, 100}, {0X3, 100}, {0X6, 100}, {0XF, 250},
		{0X0, 250}, {0XF, 250}, {0X0, 250}, {0X6, 250}, {0X0, 250}, {0X6, 250},
		{0X0, 250}
	};

	for (uint8_t i = 0; i < SHOW_SIGNAL_LEN; ++i) {
		for (uint8_t led = 0, mask = 1; led < NUM_LEDS; ++led, mask <<= 1) {
			led_state(led, show_signal[i][0] & mask);
		}
		_delay_ms(show_signal[i][1]);
	}
}

int main(void)
{
    /* Turn off global interrupts while setting up timers. */
	cli();

	/* Set up timer 1, i.e., an interrupt every 1 microsecond. */
	OCR1A = TOP1;
	TCCR1A = 0;
	TCCR1B = 0;
	TCCR1B |= (1 << WGM12);
    /* Next two lines provide a prescaler value of 8. */
	TCCR1B |= (1 << CS11);
	TCCR1B |= (1 << CS10);
	TIMSK1 |= (1 << OCIE1A);

	/* Set up timer 3, i.e., an interrupt every 10 milliseconds. */
	OCR3A = TOP3;
	TCCR3A = 0;
	TCCR3B = 0;
	TCCR3B |= (1 << WGM32);
    /* Next line provides a prescaler value of 64. */
	TCCR3B |= (1 << CS31);
	TIMSK3 |= (1 << OCIE3A);


	/* Turn on global interrupts */
	sei();


	// Testing code
	
	/*
	for (int i = 0; i < NUM_LEDS; ++i) {
		led_state(i, true);
		_delay_ms(1000);
	}
	
	for (int i = 0; i < NUM_LEDS; ++i) {
		led_state(i, false);
		_delay_ms(1000);
	}
	*/

	//SOS();

	//glow(2, 0.01);

	//pulse_glow(3);

	//light_show();

}
/* ***************************************************
 * ************ END OF CODE SECTION ******************
 * ***************************************************
 */
